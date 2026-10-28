require "net/http"

# Kirim semua URL sitemap sebuah host ke IndexNow (Bing, Yandex, Seznam, Naver berbagi indeks).
# Key disajikan di https://<host>/<key>.txt oleh SeoController#indexnow_key.
class IndexNowSubmitter
  class Error < StandardError; end
  ENDPOINT = URI("https://api.indexnow.org/indexnow")

  def initialize(instance, host: nil)
    @instance = instance
    @host = host || instance.primary_host
  end

  def key = @instance.indexnow_key
  def base_url = "https://#{@host}"
  def prefix = ""

  def call
    raise Error, I18n.t("indexnow.no_host") if @host.blank?
    raise Error, I18n.t("indexnow.no_key") if key.blank?
    builder = SitemapBuilder.new(base_url: base_url, prefix: prefix)
    urls = builder.all_urls
    body = { host: @host, key: key, keyLocation: "#{base_url}/#{key}.txt", urlList: urls }
    req = Net::HTTP::Post.new(ENDPOINT); req["Content-Type"] = "application/json; charset=utf-8"; req.body = body.to_json
    res = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 8, read_timeout: 30) { |h| h.request(req) }
    ok = %w[200 202].include?(res.code)
    status = "#{ok ? 'ok' : 'gagal'} HTTP #{res.code} · #{urls.size} URL · #{I18n.l(Time.current, format: :short)}"
    remember(status)
    raise Error, "HTTP #{res.code} #{res.body.to_s.truncate(120)}" unless ok
    { count: urls.size, code: res.code }
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    remember("gagal: #{e.class}")
    raise Error, e.message
  end

  # Dipanggil dari timer harian (bin/rails runner) — semua instance dengan domain aktif + host utama.
  def self.run_all
    Instance.active.find_each do |i|
      next unless i.indexnow_auto?
      d = i.domains.active.first or next
      begin
        new(i, host: d.hostname).call
      rescue Error => e
        Rails.logger.warn("[IndexNow] #{d.hostname}: #{e.message}")
      end
    end
  end

  private
  def remember(status)
    @instance.update_columns(settings: @instance.settings.merge("indexnow_last" => status), updated_at: Time.current)
  end
end
