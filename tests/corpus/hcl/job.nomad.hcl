# A Nomad job.
# ^^^^^^^^^^^^ comment
job "web" {
  # ^^^^^ string
  datacenters = ["dc1"]
  # ^^^^^^^^^ special
  type        = "service"

  group "app" {
    count = 2
    # ^^^ special

    network {
      port "http" {
        to = 8080
        #    ^^^^ number
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "nginx:1.27"
        ports = ["http"]
      }

      env {
        ENABLED = true
        #         ^^^^ constant
        RATIO   = 1.5
        #         ^^^ number
        LABEL   = "web-${NOMAD_ALLOC_INDEX}"
        #              ^^ special
      }
    }
  }
}
