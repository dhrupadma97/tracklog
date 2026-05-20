import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  // ✅ CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "*",
      },
    });
  }

  try {
    const body = await req.json();
    const {
      recipientEmail,
      recipientName,
      reportType, // 'daily' | 'weekly'
      poData,
      sessionSummary,
      spendBreakdown,
    } = body;

    const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
    if (!RESEND_API_KEY) {
      throw new Error("RESEND_API_KEY is not configured");
    }

    const reportTitle = reportType === "daily"
      ? "Daily PO Spend & Session Report"
      : "Weekly PO Spend & Session Report";

    const today = new Date();
    const dateStr = today.toLocaleDateString("en-IN", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });

    const formatINR = (amount: number): string => {
      if (amount >= 10000000) return `₹${(amount / 10000000).toFixed(2)} Cr`;
      if (amount >= 100000) return `₹${(amount / 100000).toFixed(2)} L`;
      return `₹${amount.toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;
    };

    const utilizationPct = poData?.totalPoWithTax > 0
      ? ((poData.totalSpend / poData.totalPoWithTax) * 100).toFixed(1)
      : "0.0";

    const balanceColor = poData?.remainingBalance < 0
      ? "#FF6B6B"
      : poData?.remainingBalance < poData?.totalPoWithTax * 0.2
      ? "#FFB74D"
      : "#4CAF50";

    const htmlBody = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>${reportTitle}</title>
</head>
<body style="margin:0;padding:0;background:#0D1421;font-family:'Segoe UI',Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0D1421;padding:32px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#1A2236 0%,#0D1421 100%);border-radius:16px 16px 0 0;padding:28px 32px;border-bottom:2px solid #FFCC00;">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td>
                    <div style="color:#FFCC00;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;margin-bottom:6px;">GOODYEAR SOUTH ASIA TYRES</div>
                    <div style="color:#FFFFFF;font-size:22px;font-weight:800;margin-bottom:4px;">${reportTitle}</div>
                    <div style="color:#6B7490;font-size:13px;">Generated on ${dateStr} &nbsp;·&nbsp; NATRAX Track Operations</div>
                  </td>
                  <td align="right" style="vertical-align:top;">
                    <div style="background:#FFCC00;color:#0D1421;font-size:11px;font-weight:800;padding:6px 14px;border-radius:20px;display:inline-block;text-transform:uppercase;letter-spacing:1px;">${reportType === "daily" ? "Daily" : "Weekly"}</div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- PO Overview -->
          <tr>
            <td style="background:#1A2236;padding:24px 32px 0 32px;">
              <div style="color:#6B7490;font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;margin-bottom:16px;">Purchase Order Overview</div>
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="background:#0D1421;border-radius:12px;padding:16px;border:1px solid #2A3450;">
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td style="padding:0 8px;text-align:center;border-right:1px solid #2A3450;">
                          <div style="color:#6B7490;font-size:10px;font-weight:600;margin-bottom:6px;">PO Number</div>
                          <div style="color:#4D9FFF;font-size:13px;font-weight:800;">${poData?.poNumber ?? "—"}</div>
                        </td>
                        <td style="padding:0 8px;text-align:center;border-right:1px solid #2A3450;">
                          <div style="color:#6B7490;font-size:10px;font-weight:600;margin-bottom:6px;">Total PO Value</div>
                          <div style="color:#FFFFFF;font-size:13px;font-weight:800;">${formatINR(poData?.totalPoWithTax ?? 0)}</div>
                        </td>
                        <td style="padding:0 8px;text-align:center;border-right:1px solid #2A3450;">
                          <div style="color:#6B7490;font-size:10px;font-weight:600;margin-bottom:6px;">Total Spend</div>
                          <div style="color:#FF6B6B;font-size:13px;font-weight:800;">${formatINR(poData?.totalSpend ?? 0)}</div>
                        </td>
                        <td style="padding:0 8px;text-align:center;">
                          <div style="color:#6B7490;font-size:10px;font-weight:600;margin-bottom:6px;">Balance</div>
                          <div style="color:${balanceColor};font-size:13px;font-weight:800;">${formatINR(Math.abs(poData?.remainingBalance ?? 0))}</div>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Utilisation Bar -->
          <tr>
            <td style="background:#1A2236;padding:20px 32px 0 32px;">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td>
                    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:6px;">
                      <tr>
                        <td style="color:#6B7490;font-size:11px;font-weight:600;">PO Utilisation</td>
                        <td align="right" style="color:${balanceColor};font-size:12px;font-weight:700;">${utilizationPct}% used</td>
                      </tr>
                    </table>
                    <div style="background:#2A3450;border-radius:8px;height:10px;overflow:hidden;">
                      <div style="background:${balanceColor};height:10px;width:${Math.min(parseFloat(utilizationPct), 100)}%;border-radius:8px;"></div>
                    </div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Spend Breakdown -->
          <tr>
            <td style="background:#1A2236;padding:20px 32px 0 32px;">
              <div style="color:#6B7490;font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;margin-bottom:14px;">Spend Breakdown</div>
              <table width="100%" cellpadding="0" cellspacing="0" style="background:#0D1421;border-radius:12px;border:1px solid #2A3450;overflow:hidden;">
                <tr style="border-bottom:1px solid #2A3450;">
                  <td style="padding:12px 16px;">
                    <div style="color:#FFFFFF;font-size:13px;font-weight:600;">🏎 Track Sessions</div>
                    <div style="color:#6B7490;font-size:10px;margin-top:2px;">${spendBreakdown?.totalSessions ?? 0} completed sessions</div>
                  </td>
                  <td align="right" style="padding:12px 16px;">
                    <div style="color:#FFCC00;font-size:13px;font-weight:700;">${formatINR(spendBreakdown?.trackSessions ?? 0)}</div>
                  </td>
                </tr>
                <tr style="border-bottom:1px solid #2A3450;">
                  <td style="padding:12px 16px;">
                    <div style="color:#FFFFFF;font-size:13px;font-weight:600;">⚙️ Additional Services</div>
                    <div style="color:#6B7490;font-size:10px;margin-top:2px;">EV charging, labour, refreshments, etc.</div>
                  </td>
                  <td align="right" style="padding:12px 16px;">
                    <div style="color:#FFB74D;font-size:13px;font-weight:700;">${formatINR(spendBreakdown?.additionalServices ?? 0)}</div>
                  </td>
                </tr>
                <tr style="border-bottom:1px solid #2A3450;">
                  <td style="padding:12px 16px;">
                    <div style="color:#FFFFFF;font-size:13px;font-weight:600;">🏭 Workshop Rent</div>
                    <div style="color:#6B7490;font-size:10px;margin-top:2px;">Monthly workshop booking</div>
                  </td>
                  <td align="right" style="padding:12px 16px;">
                    <div style="color:#9C88FF;font-size:13px;font-weight:700;">${formatINR(spendBreakdown?.workshopRent ?? 0)}</div>
                  </td>
                </tr>
                <tr>
                  <td style="padding:14px 16px;">
                    <div style="color:#FFFFFF;font-size:14px;font-weight:800;">Total Cumulative Spend</div>
                  </td>
                  <td align="right" style="padding:14px 16px;">
                    <div style="color:#FF6B6B;font-size:15px;font-weight:800;">${formatINR(poData?.totalSpend ?? 0)}</div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Session Log -->
          <tr>
            <td style="background:#1A2236;padding:20px 32px 0 32px;">
              <div style="color:#6B7490;font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;margin-bottom:14px;">Session Log (${reportType === "daily" ? "Today" : "This Week"})</div>
              ${
      sessionSummary && sessionSummary.length > 0
        ? `<table width="100%" cellpadding="0" cellspacing="0" style="background:#0D1421;border-radius:12px;border:1px solid #2A3450;overflow:hidden;">
                  <tr style="background:#2A3450;">
                    <td style="padding:10px 14px;color:#6B7490;font-size:10px;font-weight:700;text-transform:uppercase;">Track</td>
                    <td style="padding:10px 14px;color:#6B7490;font-size:10px;font-weight:700;text-transform:uppercase;">Duration</td>
                    <td style="padding:10px 14px;color:#6B7490;font-size:10px;font-weight:700;text-transform:uppercase;">Cost</td>
                    <td style="padding:10px 14px;color:#6B7490;font-size:10px;font-weight:700;text-transform:uppercase;">Status</td>
                  </tr>
                  ${
          sessionSummary.map((s: any, i: number) => `
                  <tr style="border-top:1px solid #2A3450;background:${i % 2 === 0 ? "#0D1421" : "#111827"};">
                    <td style="padding:10px 14px;color:#FFFFFF;font-size:12px;font-weight:600;">${s.trackName ?? "—"}</td>
                    <td style="padding:10px 14px;color:#8A94B0;font-size:12px;">${s.durationMinutes ? Math.floor(s.durationMinutes / 60) + "h " + (s.durationMinutes % 60) + "m" : "—"}</td>
                    <td style="padding:10px 14px;color:#FFCC00;font-size:12px;font-weight:700;">${formatINR(s.totalCost ?? 0)}</td>
                    <td style="padding:10px 14px;">
                      <span style="background:${s.sessionStatus === "completed" ? "#4CAF5030" : "#FFB74D30"};color:${s.sessionStatus === "completed" ? "#4CAF50" : "#FFB74D"};font-size:10px;font-weight:700;padding:3px 8px;border-radius:10px;text-transform:uppercase;">${s.sessionStatus}</span>
                    </td>
                  </tr>`).join("")
        }
                </table>`
        : `<div style="background:#0D1421;border-radius:12px;border:1px solid #2A3450;padding:20px;text-align:center;color:#6B7490;font-size:13px;">No sessions recorded ${reportType === "daily" ? "today" : "this week"}</div>`
    }
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background:#1A2236;border-radius:0 0 16px 16px;padding:24px 32px;margin-top:20px;border-top:1px solid #2A3450;">
              <div style="color:#4A5470;font-size:11px;text-align:center;line-height:1.6;">
                This is an automated ${reportType} report from <strong style="color:#6B7490;">TrackLog — NATRAX Operations</strong><br/>
                Goodyear South Asia Tyres Pvt. Limited · PO #${poData?.poNumber ?? "—"}<br/>
                <span style="color:#3A4460;">Do not reply to this email. Manage your report preferences in the TrackLog app.</span>
              </div>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

    const emailPayload = {
      from: "onboarding@resend.dev",
      to: [recipientEmail],
      subject: `[TrackLog] ${reportTitle} — ${dateStr}`,
      html: htmlBody,
    };

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify(emailPayload),
    });

    const resendData = await resendResponse.json();

    if (!resendResponse.ok) {
      throw new Error(
        `Resend API error: ${resendData.message ?? resendResponse.statusText}`,
      );
    }

    return new Response(
      JSON.stringify({ success: true, emailId: resendData.id }),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      },
    );
  }
});
