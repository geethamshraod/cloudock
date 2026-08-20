resource "google_monitoring_uptime_check_config" "cloudock" {
  display_name = "cloudock-uptime-check"
  timeout      = "10s"
  period       = "300s"

  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]

  http_check {
    path    = "/health"
    port    = 443
    use_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      # Derived directly from the deployed service instead of a manual
      # [CLOUD-RUN-URL] placeholder -- creates a real dependency, and
      # avoids the https:// prefix (invalid for a bare "host" label) that
      # copying the URL directly would have included.
      host = replace(google_cloud_run_v2_service.dashboard.uri, "https://", "")
    }
  }
}

resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "cloudock-error-rate-alert"
  combiner      = "OR"

  conditions {
    display_name = "5xx error rate"

    condition_threshold {
      # Fixed: the original had unescaped double quotes nested inside a
      # double-quoted string -- invalid HCL, same bug class as the
      # CyberArk connector's filter string several sessions back.
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.response_code_class=\"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "60s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # var.notification_channel_id defaults to [] -- the alert policy will
  # still be created and will still fire, it just won't notify anyone
  # until a real channel ID is supplied. Create one (email is simplest)
  # via Console -> Monitoring -> Alerting -> Notification Channels first.
  notification_channels = var.notification_channel_id

  documentation {
    content = "Cloud Run error rate exceeded 5% for 60 seconds -- check Cloud Run logs"
  }
}
