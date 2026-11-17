# Demo service with canary deployments and automatic rollback.
# Lab only. Image and failure switches come in as variables (see scripts/deploy.sh).

variable "image" {
  type        = string
  description = "Full image reference, tagged with the git SHA (never :latest)"
}

variable "fail_health" {
  type    = string
  default = "false"
}

variable "crash_on_start" {
  type    = string
  default = "false"
}

variable "startup_delay_ms" {
  type    = string
  default = "0"
}

# Only flipped to false by scripts/time-rollback.sh to time a MANUAL rollback.
variable "auto_revert" {
  type    = bool
  default = true
}

job "demo" {
  datacenters = ["lab"]
  type        = "service"

  group "web" {
    # 2+ so a canary is meaningful: old allocs keep serving while the canary is judged.
    count = 2

    # Defined once, at group level, on purpose. A group-level update block silently
    # overrides a job-level one, so keeping a single block avoids surprises.
    update {
      max_parallel      = 1
      canary            = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "45s"
      progress_deadline = "90s"
      auto_revert       = var.auto_revert
      auto_promote      = true
    }

    network {
      port "http" {
        to = 8080
      }
    }

    # A crash-looping task must not hide behind endless restarts/reschedules,
    # otherwise the deployment never gets a clean "unhealthy" signal.
    restart {
      attempts = 1
      interval = "5m"
      delay    = "5s"
      mode     = "fail"
    }

    reschedule {
      attempts  = 0
      unlimited = false
    }

    service {
      name     = "demo"
      port     = "http"
      provider = "consul"

      check {
        name     = "demo-health"
        type     = "http"
        path     = "/health"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "app" {
      driver = "docker"

      config {
        image = var.image
        ports = ["http"]
      }

      env {
        FAIL_HEALTH      = var.fail_health
        CRASH_ON_START   = var.crash_on_start
        STARTUP_DELAY_MS = var.startup_delay_ms
      }

      resources {
        cpu    = 100
        memory = 128
      }

      kill_timeout = "10s"
    }
  }
}
