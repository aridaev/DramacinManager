# Mengukur waktu respons tiap provider (panggilan home langsung ke host, tanpa cache) dan menyimpan
# median ke providers.last_latency_ms. Template v1 mengurutkan pemilih provider berdasarkan nilai ini.
#   bin/rails dracin:latency          # semua provider yang punya adapter
#   bin/rails dracin:latency[3]       # 3 sampel per provider (default 2)
namespace :dracin do
  desc "Ukur latency home tiap provider dan simpan ke providers.last_latency_ms"
  task :latency, [ :samples ] => :environment do |_, args|
    samples = [ args[:samples].to_i, 1 ].max.then { |n| n == 1 && args[:samples].nil? ? 2 : n }
    key = Setting.dracin_api_key
    abort "DracinAPI key belum diset" if key.blank?
    providers = Provider.supported.ordered.to_a
    results = {}

    threads = providers.map do |pr|
      Thread.new do
        Rails.application.executor.wrap do
          times = samples.times.map do
            adapter = DracinApi::Adapters.for(pr, api_key: key, lang: "id")
            t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            begin
              Rails.cache.delete([ "dracin_api", "moboreels", "series_list" ]) if pr.slug == "moboreels"
              items = adapter.home.sum { |s| s.items.size }
              ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000).round
              items.zero? ? nil : ms
            rescue DracinApi::Error, StandardError
              nil
            end
          end
          results[pr.slug] = times
        end
      end
    end
    threads.each(&:join)

    now = Time.current
    providers.each do |pr|
      ok = results[pr.slug].compact.sort
      median = ok.empty? ? nil : ok[ok.size / 2]
      pr.update_columns(last_latency_ms: median, last_checked_at: now)
      puts format("%-12s %s", pr.slug, median ? "#{median} ms (#{ok.size}/#{samples} ok)" : "GAGAL/kosong")
    end
    puts "Urutan tercepat: " + providers.sort_by { |p| p.last_latency_ms || 10**9 }.map(&:slug).join(" > ")
  end
end
