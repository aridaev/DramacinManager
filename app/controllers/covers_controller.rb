require "net/http"

# Proxy poster drama: dipakai saat gambar asli gagal dimuat di browser (hotlink/referrer/CORS diblok CDN).
# GET /covers?u=<url>. Hanya http(s), maks 6 MB, cache 1 hari.
class CoversController < ActionController::Base
  protect_from_forgery with: :null_session
  MAX_BYTES = 6 * 1024 * 1024

  def show
    uri = URI.parse(params[:u].to_s) rescue nil
    return head :bad_request unless uri.is_a?(URI::HTTP) && uri.host.present?

    body, type = Rails.cache.fetch([ "cover", uri.to_s ], expires_in: 1.day) { fetch(uri) }
    return head :not_found if body.blank?
    expires_in 1.day, public: true
    send_data body, type: type, disposition: "inline"
  end

  private
  def fetch(uri, hops = 0)
    return nil if hops > 3
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36"
    req["Accept"] = "image/avif,image/webp,image/*,*/*;q=0.8"
    req["Referer"] = "#{uri.scheme}://#{uri.host}/"
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 12) { |h| h.request(req) }
    if res.is_a?(Net::HTTPRedirection) && res["location"].present?
      return fetch(URI.join(uri.to_s, res["location"]), hops + 1)
    end
    return nil unless res.is_a?(Net::HTTPSuccess)
    type = res["content-type"].to_s.split(";").first.presence || "image/jpeg"
    return nil unless type.start_with?("image/") || type == "application/octet-stream"
    return nil if res.body.to_s.bytesize > MAX_BYTES
    [ res.body, (type == "application/octet-stream" ? "image/jpeg" : type) ]
  rescue StandardError
    nil
  end
end
