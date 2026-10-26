import QtQuick
import qs.Commons
import qs.Commons as Commons

// Latency readout for one proxy. Reads straight off the service so it updates
// on its own during a probe and after every /proxies poll.
Badge {
  id: root

  property var svc: null
  property string proxyName: ""
  property color foreground: Commons.Color.popups.text

  readonly property int ms: svc ? svc.delayOf(proxyName) : -1
  readonly property bool busy: svc ? svc.isTesting(proxyName) : false

  // mihomo reports a failed probe as 0, and -1 is our own "never probed".
  text: busy ? "···"
    : ms < 0 ? "--"
    : ms === 0 ? (svc ? svc.t("timeout") : "timeout")
    : String(ms)

  tint: busy || ms < 0 ? Util.alpha(foreground, 0.45)
    : ms === 0 ? Commons.Color.urgent
    : ms <= 250 ? Commons.Color.accent
    : Util.alpha(foreground, 0.62)
}
