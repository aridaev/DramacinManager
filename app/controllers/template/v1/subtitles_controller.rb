require "net/http"

# Proxy subtitle same-origin: <track> di browser butuh CORS dari host subtitle (jarang tersedia), dan banyak
# provider mengirim SRT. URL harus ditandatangani server (MessageVerifier) agar ini bukan open proxy.
class Template::V1::SubtitlesController < ActionController::Base
  MAX_BYTES = 1.megabyte
  TOKEN_TTL = 6.hours

  def self.signed_path(url)
    Rails.application.routes.url_helpers.template_v1_subtitle_path(t: verifier.generate(url.to_s, expires_in: TOKEN_TTL, purpose: :tv1_subtitle))
  end

  def self.token_for(url) = verifier.generate(url.to_s, expires_in: TOKEN_TTL, purpose: :tv1_subtitle)

  def self.verifier = Rails.application.message_verifier(:tv1_subtitle)

  def show
    url = self.class.verifier.verified(params[:t].to_s, purpose: :tv1_subtitle) or return head(:forbidden)
    body = Rails.cache.fetch([ "tv1_subtitle", url ], expires_in: TOKEN_TTL) { fetch_vtt(url) }
    return head(:bad_gateway) if body.nil?
    expires_in 1.hour, public: true
    render plain: body, content_type: "text/vtt"
  end

  private
  def fetch_vtt(url, redirects = 2)
    uri = URI.parse(url)
    return nil unless uri.is_a?(URI::HTTPS) || uri.is_a?(URI::HTTP)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "DracinManager/1.0"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
    if response.is_a?(Net::HTTPRedirection) && redirects.positive? && response["Location"].present?
      return fetch_vtt(URI.join(uri, response["Location"]).to_s, redirects - 1)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)
    body = response.body.to_s.byteslice(0, MAX_BYTES).dup.force_encoding("UTF-8").scrub
    body = body.delete_prefix("\uFEFF")
    body.lstrip.start_with?("WEBVTT") ? body : srt_to_vtt(body)
  rescue StandardError => e
    Rails.logger.warn("[tv1 subtitle] #{url}: #{e.class} #{e.message}")
    nil
  end

  def srt_to_vtt(srt)
    text = srt.gsub("\r\n", "\n")
    text = text.gsub(/^\d+\n(?=\d{2}:\d{2}:\d{2}[,.]\d{3})/, "")                       # nomor cue
    text = text.gsub(/(\d{2}:\d{2}:\d{2}),(\d{3})/, '\1.\2')                           # koma → titik
    "WEBVTT\n\n#{text.strip}\n"
  end
end
