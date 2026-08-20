# Real rules this time -- M2's armor-policy was created empty and
# explicitly flagged in that milestone's decision log as unfinished work.
# This is that follow-up.
resource "google_compute_security_policy" "cloudock" {
  name = "armor-policy"

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
        expression = "evaluatePreconfiguredExpr('scanner-detection-stable')"
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
