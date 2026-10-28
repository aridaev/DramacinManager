require "net/http"

# Proxy logo provider. Hub logo (api.dramabuzz.sbs) mengirim Cross-Origin-Resource-Policy: same-origin,
# sehingga browser menolak <img> lintas origin; di sini diambil server-side lalu di-cache.
class ProviderLogosController < ActionController::Base
  TTL = 1.day
  MAX_BYTES = 2.megabytes

  def show
    provider = Provider.find_by(slug: params[:slug])
    return head(:not_found) if provider.nil? || provider.logo_url.blank?
    data = Rails.cache.fetch([ "provider_logo", provider.logo_url ], expires_in: TTL, skip_nil: true) { fetch_logo(provider.logo_url) }
    return head(:not_found) if data.nil?
    expires_in TTL, public: true
    send_data data[:body], type: data[:type], disposition: "inline"
  end

  private
  def fetch_logo(url)
    uri = URI(url)
    return nil unless uri.is_a?(URI::HTTP)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |h|
      h.get(uri.request_uri, "User-Agent" => "DracinManager", "Accept" => "image/*")
    end
    return nil unless res.is_a?(Net::HTTPSuccess) && res.body.to_s.bytesize.between?(1, MAX_BYTES)
    unwrap(res.body, res["content-type"].to_s.split(";").first.strip)
  rescue StandardError => e
    Rails.logger.warn("[ProviderLogo] #{url}: #{e.class} #{e.message}")
    nil
  end

  # Hub membungkus bitmap di <svg><image href="data:image/png;base64,..."/></svg> (sering WebP/JPEG
  # berlabel png); ambil bitmapnya langsung dan tentukan tipe dari magic bytes.
  def unwrap(body, type)
    if type == "image/svg+xml" && (m = body.match(%r{<image[^>]+href="data:image/[a-z+]+;base64,([^"]+)"}))
      bin = Base64.decode64(m[1])
      real = sniff(bin)
      return { body: bin, type: real } if real
    end
    return nil unless type.start_with?("image/")
    { body: body, type: type }
  end

  def sniff(bin)
    return "image/png"  if bin.start_with?("\x89PNG".b)
    return "image/jpeg" if bin.start_with?("\xFF\xD8".b)
    return "image/webp" if bin.start_with?("RIFF".b) && bin.byteslice(8, 4) == "WEBP"
    return "image/gif"  if bin.start_with?("GIF8".b)
    nil
  end
end
