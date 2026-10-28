namespace :dracin do
  desc "Cek status zone Cloudflare untuk domain yang masih menunggu NS (cron)"
  task domains_refresh: :environment do
    client = CloudflareClient.from_settings
    next puts("cloudflare belum dikonfigurasi") unless client.configured?
    Domain.pending_ns.where.not(cf_zone_id: nil).find_each do |d|
      d.refresh_status!(client)
      puts "#{Time.current.iso8601} #{d.hostname} -> #{d.status} (cf=#{d.cf_status})"
    end
  end
end
