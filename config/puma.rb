# Production: cluster mode (2 worker) tanpa preload_app agar `systemctl reload` (SIGUSR1 = phased restart)
# mengganti worker satu per satu tanpa downtime. Solid Queue berjalan di service terpisah (dracinmanager-jobs).
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

workers ENV.fetch("WEB_CONCURRENCY", 2).to_i if ENV["RAILS_ENV"] == "production"
preload_app! false
worker_timeout 90

bind "unix:///var/www/DracinManager/tmp/sockets/puma.sock"

plugin :tmp_restart
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
