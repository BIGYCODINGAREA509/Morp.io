import { withSupabase } from "npm:@supabase/server@1";
import webpush from "npm:web-push@3.6.7";

type Subscription = {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
};

type SubscriptionRow = {
  endpoint: string;
  user_id: string;
  subscription: Subscription;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isAllowedPushEndpoint(endpoint: string): boolean {
  try {
    const url = new URL(endpoint);
    const host = url.hostname.toLowerCase();
    return url.protocol === "https:" &&
      (host === "fcm.googleapis.com" ||
        host === "updates.push.services.mozilla.com" ||
        host === "push.services.mozilla.com" ||
        host === "web.push.apple.com" ||
        /^[a-z0-9-]+\.notify\.windows\.com$/.test(host));
  } catch {
    return false;
  }
}

export default {
  fetch: withSupabase({ auth: "secret" }, async (request, { supabaseAdmin }) => {
    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405 });
    }

    let payload: unknown;
    try {
      payload = await request.json();
    } catch {
      return Response.json({ error: "Invalid JSON" }, { status: 400 });
    }
    if (!isRecord(payload) || payload.type !== "INSERT" || payload.schema !== "public" ||
      !isRecord(payload.record)) {
      return Response.json({ ignored: true });
    }

    const table = payload.table;
    const record = payload.record;
    const senderId = typeof record.user_id === "string" ? record.user_id : "";
    const message = typeof record.body === "string" ? record.body.trim() : "";
    if (!senderId || !message) {
      return Response.json({ error: "Invalid message record" }, { status: 400 });
    }

    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const subject = Deno.env.get("VAPID_SUBJECT");
    if (!publicKey || !privateKey || !subject) {
      console.error("Web Push VAPID secrets are not configured.");
      return Response.json({ error: "Push is not configured" }, { status: 500 });
    }
    webpush.setVapidDetails(subject, publicKey, privateKey);

    let title: string;
    let body: string;
    let tag: string;
    let url: string;
    let subscriptionsQuery = supabaseAdmin
      .from("push_subscriptions")
      .select("endpoint,user_id,subscription");

    if (table === "admin_messages") {
      const fromAdmin = record.from_admin === true;
      if (fromAdmin) {
        url = "./index.html?openMessages=admin";
        subscriptionsQuery = subscriptionsQuery.eq("user_id", senderId);
        title = "Nouvo mesaj nan men administratè a";
        tag = `morpio-admin-${senderId}`;
      } else {
        url = `./admin.html?openMessages=thread&userId=${encodeURIComponent(senderId)}`;
        const { data: admins, error: adminsError } = await supabaseAdmin
          .from("profiles")
          .select("id")
          .eq("is_admin", true);
        if (adminsError) {
          console.error("Could not load admin recipients:", adminsError.message);
          return Response.json({ error: "Could not load recipients" }, { status: 500 });
        }
        const adminIds = (admins || []).map(admin => String(admin.id)).filter(Boolean);
        if (!adminIds.length) return Response.json({ sent: 0 });
        subscriptionsQuery = subscriptionsQuery.in("user_id", adminIds);
        title = "Nouvo mesaj yon jwè voye";
        tag = "morpio-admin-inbox";
      }

      const { data: sender, error: senderError } = await supabaseAdmin
        .from("profiles")
        .select("username")
        .eq("id", senderId)
        .maybeSingle();
      if (senderError) console.error("Could not load message sender:", senderError.message);
      body = fromAdmin
        ? "Administratè a voye w yon nouvo mesaj prive."
        : `${sender?.username || "Yon jwè"} voye w yon nouvo mesaj prive.`;
    } else if (table === "player_chat_messages") {
      url = "./index.html?openMessages=public";
      subscriptionsQuery = subscriptionsQuery.neq("user_id", senderId);
      const { data: sender, error: senderError } = await supabaseAdmin
        .from("profiles")
        .select("username")
        .eq("id", senderId)
        .maybeSingle();
      if (senderError) console.error("Could not load chat sender:", senderError.message);
      title = "Nouvo mesaj nan chat jwè yo";
      body = `${sender?.username || "Yon jwè"}: ${message}`;
      tag = "morpio-public-chat";
    } else {
      return Response.json({ ignored: true });
    }

    const { data: subscriptions, error: subscriptionsError } = await subscriptionsQuery;
    if (subscriptionsError) {
      console.error("Could not load push subscriptions:", subscriptionsError.message);
      return Response.json({ error: "Could not load subscriptions" }, { status: 500 });
    }

    const notification = JSON.stringify({
      title,
      body: body.slice(0, 240),
      tag,
      url
    });
    const expiredEndpoints: string[] = [];
    let sent = 0;
    let failed = 0;

    for (let offset = 0; offset < (subscriptions || []).length; offset += 50) {
      const batch = (subscriptions || []).slice(offset, offset + 50) as SubscriptionRow[];
      const results = await Promise.allSettled(batch.map(async row => {
        if (!isAllowedPushEndpoint(row.endpoint)) {
          throw new Error("Unsupported push endpoint");
        }
        await webpush.sendNotification(row.subscription, notification, { TTL: 3600, urgency: "high" });
      }));

      results.forEach((result, index) => {
        if (result.status === "fulfilled") {
          sent++;
          return;
        }
        failed++;
        const reason: unknown = result.reason;
        const statusCode = isRecord(reason) && typeof reason.statusCode === "number" ? reason.statusCode : 0;
        if (statusCode === 404 || statusCode === 410) expiredEndpoints.push(batch[index].endpoint);
        else console.error("Web Push delivery failed:", reason);
      });
    }

    if (expiredEndpoints.length) {
      const { error } = await supabaseAdmin.from("push_subscriptions").delete().in("endpoint", expiredEndpoints);
      if (error) console.error("Could not remove expired push subscriptions:", error.message);
    }

    return Response.json({ sent, failed, expired: expiredEndpoints.length });
  })
};
