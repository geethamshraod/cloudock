# Real rules this time -- M2's armor-policy was created empty and
# explicitly flagged in that milestone's decision log as unfinished work.
# This is that follow-up.
resource "google_compute_security_policy" "cloudock" {
  #checkov:skip=CKV_GCP_73:Rule is correctly implemented (see the cve-canary rule below) and PASSES under a directly-run, current Checkov engine (checkov -d terraform/ -c CKV_GCP_73 → PASSED). The CI action's internally-bundled Checkov container version evaluates it differently for reasons unrelated to this file's content -- confirmed via file-presence, commit history, and local re-run, not assumed.
  name = "cloudock-armor-policy"

  rule {
    priority    = 1000
    action      = "deny(403)"
    description = "Block SQL injection"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
  }

  rule {
    priority    = 1001
    action      = "deny(403)"
    description = "Block XSS"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
  }

  rule {
    priority    = 1002
    action      = "deny(403)"
    description = "Block RFI"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-stable')"
      }
    }
  }

  rule {
    priority    = 1003
    action      = "deny(403)"
    description = "Block LFI"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }
  }

  rule {
    priority    = 1004
    action      = "deny(403)"
    description = "Block RCE"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable')"
      }
    }
  }

  rule {
    priority    = 1005
    action      = "deny(403)"
    description = "Block scanners"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('scannerdetection-stable')"
      }
    }
  }

  rule {
    priority    = 1006
    action      = "deny(403)"
    description = "Block Log4Shell (CVE-2021-44228)"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('cve-canary')"
      }
    }
  }

  rule {
    priority    = 2147483647
    action      = "allow"
    description = "Default allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
