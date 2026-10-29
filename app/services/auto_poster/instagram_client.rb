require "net/http"

module AutoPoster
  # Unggah Reels lewat endpoint web Instagram (sama seperti browser Chrome desktop di instagram.com):
  #   1. GET  https://www.instagram.com/            → ambil fb_dtsg + x-instagram-ajax (rollout hash) + csrftoken terbaru
  #   2. POST https://i.instagram.com/rupload_igvideo/fb_uploader_<id>   (video, x-instagram-rupload-params)
  #   3. POST https://i.instagram.com/rupload_igphoto/fb_uploader_<id>   (cover jpg, sama upload_id)
  #   4. POST https://www.instagram.com/api/v1/media/configure_to_clips/ (caption) — 202 = masih transcoding, ulangi
  # Semua header (UA, sec-ch-ua, sec-fetch-*, Accept-Language, x-ig-app-id, x-asbd-id) disamakan dengan browser asli.
  class InstagramClient
    class Error < StandardError; end
    class AuthError < Error; end

    CHROME_VERSION = "130"
    UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/#{CHROME_VERSION}.0.0.0 Safari/537.36".freeze
    SEC_CH_UA = %("Chromium";v="#{CHROME_VERSION}", "Google Chrome";v="#{CHROME_VERSION}", "Not?A_Brand";v="99").freeze
    IG_APP_ID = "936619743392459".freeze
    ASBD_ID = "359341".freeze
    DEFAULT_AJAX = "1042267535".freeze
    OPEN_TIMEOUT = 15
    READ_TIMEOUT = 180

    Result = Struct.new(:media_id, :code, :url, keyword_init: true)

    def initialize(cookie_header)
      @cookie = cookie_header.to_s
      @csrf = AutoPost.cookie_value(@cookie, "csrftoken").to_s
      @ajax = DEFAULT_AJAX
      @dtsg = nil
    end

    def post_reel(video_path, cover_path, caption, width:, height:, duration_ms:)
      bootstrap!
      upload_id = (Time.now.to_f * 1000).to_i.to_s
      upload_video(upload_id, video_path, width, height, duration_ms)
      upload_cover(upload_id, cover_path, width, height)
      configure(upload_id, caption)
    end

    private
    # Ambil token halaman: fb_dtsg, rollout hash (x-instagram-ajax) dan csrftoken (bisa di-rotate lewat Set-Cookie).
    def bootstrap!
      res = request(:get, "https://www.instagram.com/", nil, navigate_headers)
      raise AuthError, "cookie tidak valid / sesi habis (HTTP #{res.code})" unless res.is_a?(Net::HTTPSuccess)
      body = res.body.to_s
      raise AuthError, "cookie tidak login (halaman login)" if body.include?("\"login_page\"") || body.match?(/<title>Login/i) || !body.include?("ds_user_id")
      @dtsg = body[/"DTSGInitialData",\[\],\{"token":"([^"]+)"/, 1] || body[/\{"dtsg":\{"token":"([^"]+)"/, 1] || body[/"fb_dtsg":"([^"]+)"/, 1]
      @ajax = body[/"rollout_hash":"([^"]+)"/, 1] || @ajax
      new_csrf = res.get_fields("set-cookie").to_a.map { |c| c[/\Acsrftoken=([^;]+)/, 1] }.compact.last
      if new_csrf.present? && new_csrf != @csrf
        @csrf = new_csrf
        @cookie = @cookie.sub(/(?:\A|;\s*)csrftoken=[^;]*/) { |m| m.sub(/csrftoken=.*/, "csrftoken=#{new_csrf}") }
      end
      raise AuthError, "fb_dtsg tidak ditemukan" if @dtsg.blank?
    end

    def upload_video(upload_id, path, w, h, dur)
      params = { client_passthrough: "1", is_clips_video: "1", is_sidecar: "0", media_type: 2, for_album: false, video_format: "",
                 upload_id: upload_id, upload_media_duration_ms: dur, upload_media_height: h, upload_media_width: w, video_transform: nil }
      rupload("rupload_igvideo", upload_id, File.binread(path), "video/mp4", params)
    end

    def upload_cover(upload_id, path, w, h)
      params = { media_type: 2, upload_id: upload_id, upload_media_height: h, upload_media_width: w }
      rupload("rupload_igphoto", upload_id, File.binread(path), "image/jpeg", params)
    end

    def rupload(kind, upload_id, data, mime, params)
      name = "fb_uploader_#{upload_id}"
      hdr = api_headers.merge(
        "x-instagram-rupload-params" => params.to_json, "x-entity-name" => name, "x-entity-length" => data.bytesize.to_s,
        "x-entity-type" => mime, "offset" => "0", "content-type" => kind == "rupload_igvideo" ? "application/octet-stream" : mime,
        "accept" => "*/*", "sec-fetch-site" => "same-site", "sec-fetch-mode" => "cors", "sec-fetch-dest" => "empty"
      )
      res = request(:post, "https://i.instagram.com/#{kind}/#{name}", data, hdr)
      raise AuthError, "sesi ditolak saat unggah (#{res.code})" if %w[401 403].include?(res.code)
      raise Error, "#{kind} gagal: HTTP #{res.code} #{res.body.to_s.first(200)}" unless res.is_a?(Net::HTTPSuccess)
      json = JSON.parse(res.body) rescue {}
      raise Error, "#{kind}: #{json['message'] || res.body.to_s.first(200)}" unless json["status"] == "ok" || json["upload_id"].present?
    end

    def configure(upload_id, caption)
      form = {
        archive_only: "false", caption: caption, clips_share_preview_to_feed: "1", disable_comments: "0", disable_oa_reuse: "false",
        igtv_share_preview_to_feed: "1", is_meta_only_post: "0", is_unified_video: "1", like_and_view_counts_disabled: "0",
        media_share_flow: "creation_flow", share_to_facebook: "", source_type: "library", upload_id: upload_id,
        video_subtitles_enabled: "0", jazoest: jazoest, fb_dtsg: @dtsg
      }
      body = URI.encode_www_form(form)
      hdr = api_headers.merge("content-type" => "application/x-www-form-urlencoded", "accept" => "*/*", "x-requested-with" => "XMLHttpRequest",
                              "sec-fetch-site" => "same-origin", "sec-fetch-mode" => "cors", "sec-fetch-dest" => "empty")
      res = nil
      12.times do |i|
        sleep(i.zero? ? 3 : 5)
        res = request(:post, "https://www.instagram.com/api/v1/media/configure_to_clips/", body, hdr)
        break unless res.code == "202" # 202 = transcode belum selesai
      end
      raise AuthError, "sesi ditolak saat configure (#{res.code})" if %w[401 403].include?(res.code)
      json = JSON.parse(res.body) rescue {}
      raise Error, "configure gagal: HTTP #{res.code} #{json['message'] || res.body.to_s.first(200)}" unless res.is_a?(Net::HTTPSuccess) && json["status"] == "ok"
      media = json["media"] || {}
      Result.new(media_id: media["id"] || media["pk"], code: media["code"], url: media["code"] ? "https://www.instagram.com/reel/#{media['code']}/" : nil)
    end

    # jazoest = "2" + jumlah kode karakter csrftoken (perhitungan yang dipakai web IG/FB).
    def jazoest = "2#{@csrf.sum}"

    def navigate_headers
      {
        "user-agent" => UA, "accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "accept-language" => "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7", "accept-encoding" => "identity", "cookie" => @cookie,
        "sec-ch-ua" => SEC_CH_UA, "sec-ch-ua-mobile" => "?0", "sec-ch-ua-platform" => '"Windows"',
        "sec-fetch-site" => "none", "sec-fetch-mode" => "navigate", "sec-fetch-user" => "?1", "sec-fetch-dest" => "document",
        "upgrade-insecure-requests" => "1", "cache-control" => "max-age=0"
      }
    end

    def api_headers
      {
        "user-agent" => UA, "accept-language" => "id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7", "accept-encoding" => "identity", "cookie" => @cookie,
        "origin" => "https://www.instagram.com", "referer" => "https://www.instagram.com/",
        "x-csrftoken" => @csrf, "x-ig-app-id" => IG_APP_ID, "x-asbd-id" => ASBD_ID, "x-instagram-ajax" => @ajax, "x-ig-max-touch-points" => "0",
        "x-ig-www-claim" => "0", "sec-ch-ua" => SEC_CH_UA, "sec-ch-ua-mobile" => "?0", "sec-ch-ua-platform" => '"Windows"'
      }
    end

    def request(method, url, body, headers)
      uri = URI.parse(url)
      req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body if body
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |h| h.request(req) }
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Error, "koneksi Instagram: #{e.class}"
    end
  end
end
