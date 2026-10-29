require "open3"
require "json"
require "net/http"

module AutoPoster
  # Mengunduh episode (HLS/MP4, termasuk stream ber-cookie) dan merender ulang ke spesifikasi Reels:
  # 1080x1920 (9:16), H.264 high + AAC 128k, 30 fps, maks N detik. Video yang bukan 9:16 diletakkan di tengah
  # dengan latar blur. Watermark instance DIBAKAR ke frame (gambar watermark_src; fallback teks nama aplikasi)
  # sehingga tetap ada setelah diunggah ke Instagram.
  #
  # Remix (remix_seed): variasi kecil yang deterministik per akun+episode — kecepatan ±3-5 % (video+audio), nada
  # audio digeser 2-3 %, zoom-crop 3-8 %, hue/saturasi/kecerahan sedikit, awal digeser <1,2 s. Tidak terasa oleh
  # penonton tetapi mengubah sidik jari audio/visual sehingga tidak identik dengan sumber maupun unggahan akun lain.
  #
  # Musik latar pelan (bgm): dicampur ke audio episode pada volume rendah (dialog tetap jelas) sehingga fingerprint
  # audio makin berbeda. Berkas di storage/bgm/*.{mp3,m4a,wav,ogg} (bebas royalti, dipilih deterministik dari seed
  # dan di-loop); bila folder kosong dipakai pad sintetis dari ffmpeg (akord lembut + lowpass, tanpa hak cipta).
  class VideoBuilder
    class Error < StandardError; end

    W = 1080
    H = 1920
    MARGIN = 48
    BOTTOM_SAFE = 300 # area bawah Reels tertutup caption/ikon → watermark bawah dinaikkan
    WM_HEIGHT = { "small" => 80, "medium" => 120, "large" => 170, "xlarge" => 240 }.freeze
    WM_POS = {
      "top-center"   => [ "(W-w)/2", MARGIN.to_s ],
      "top-left"     => [ MARGIN.to_s, MARGIN.to_s ],
      "top-right"    => [ "W-w-#{MARGIN}", MARGIN.to_s ],
      "bottom-left"  => [ MARGIN.to_s, "H-h-#{BOTTOM_SAFE}" ],
      "bottom-right" => [ "W-w-#{MARGIN}", "H-h-#{BOTTOM_SAFE}" ]
    }.freeze
    UA = Template::V1::StreamsController::USER_AGENT
    FONT = (Dir.glob("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf") + Dir.glob("/usr/share/fonts/truetype/**/*-Bold.ttf")).first
    DEFAULT_HOST = ENV.fetch("DRACIN_HOST", "dracin.aridaev.com")

    # offset_seconds: titik mulai potongan (Part ke-n = (n-1) * max_seconds).
    def initialize(instance, stream, dir, max_seconds: 90, offset_seconds: 0, remix_seed: nil, bgm: false)
      @instance, @stream, @dir = instance, stream, dir
      @remix = remix_seed ? remix_params(remix_seed) : nil
      @bgm = bgm ? bgm_source(remix_seed.to_i) : nil
      @max = max_seconds.to_i.clamp(AutoPost::MIN_SECONDS, AutoPost::MAX_SECONDS)
      @offset = [ offset_seconds.to_i, 0 ].max
    end

    # Durasi sumber (detik), dari ffprobe (sekali; dipakai juga oleh build).
    def source_duration = source_meta.dig("format", "duration").to_f

    # Faktor kecepatan (1.0 tanpa remix); satu part keluaran = max_seconds * speed detik sumber.
    def speed = @remix ? @remix[:speed] : 1.0
    # Jumlah part untuk episode ini; sisa < 5 detik tidak dijadikan part sendiri.
    def parts = [ ((source_duration - 5) / (@max * speed)).ceil, 1 ].max
    def remix? = @remix.present?
    def bgm? = @bgm.present?

    # => [mp4_path, cover_jpg_path, { width:, height:, duration_ms: }]
    def build
      meta = source_meta
      has_audio = Array(meta["streams"]).any? { |s| s["codec_type"] == "audio" }
      vs = Array(meta["streams"]).find { |s| s["codec_type"] == "video" } || {}
      portrait = vs["width"].to_i > 0 && ((vs["width"].to_f / vs["height"].to_i) - (W.to_f / H)).abs < 0.02
      wm = fetch_watermark
      out = File.join(@dir, "reel.mp4")
      cover = File.join(@dir, "cover.jpg")

      cmd = [ "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-nostdin", *input_opts ]
      ss = @offset * speed + (@remix ? @remix[:skip] : 0)
      cmd += [ "-ss", format("%.2f", ss) ] if ss.positive?
      cmd += [ "-i", @stream.url ]
      cmd += [ "-i", wm ] if wm
      idx = wm ? 2 : 1
      null_idx = bgm_idx = nil
      unless has_audio
        cmd += [ "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100" ]
        null_idx = idx; idx += 1
      end
      if @bgm
        cmd += @bgm[:file] ? [ "-stream_loop", "-1", "-i", @bgm[:file] ] : [ "-f", "lavfi", "-i", @bgm[:lavfi] ]
        bgm_idx = idx
      end
      a_graph, audio_map = audio_graph(has_audio, null_idx, bgm_idx)
      cmd += [ "-filter_complex", filter_graph(wm, portrait) + a_graph, "-map", "[v]", "-map", audio_map, "-t", @max.to_s,
               "-c:v", "libx264", "-preset", "superfast", "-profile:v", "high", "-level", "4.1", "-pix_fmt", "yuv420p",
               "-r", "30", "-g", "60", "-crf", "23", "-maxrate", "5M", "-bufsize", "10M",
               "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2", "-shortest", "-movflags", "+faststart", out ]
      run!(cmd, timeout: 900)
      run!([ "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", "1", "-i", out, "-frames:v", "1", "-q:v", "2", cover ], timeout: 60)
      raise Error, "output kosong" unless File.size?(out) && File.size?(cover)

      info = probe(out, [])
      [ out, cover, { width: W, height: H, duration_ms: (info.dig("format", "duration").to_f * 1000).round, source_duration_ms: (source_duration * 1000).round } ]
    end

    private
    def source_meta = @source_meta ||= probe(@stream.url, input_opts)

    # Header seperti browser; cookie stream (mis. Vigloo) diteruskan ke ffmpeg.
    def input_opts
      hdr = "Referer: https://#{DEFAULT_HOST}/\r\n"
      hdr += "Cookie: #{@stream.cookies.map { |k, v| "#{k}=#{v}" }.join('; ')}\r\n" if @stream.cookies.present?
      [ "-user_agent", UA, "-headers", hdr, "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5" ]
    end

    # Sumber yang sudah 9:16 cukup di-scale (tanpa latar blur). Latar blur dihitung pada resolusi kecil
    # (1/4) lalu diperbesar — hasil visual sama, jauh lebih ringan daripada boxblur di 1080x1920.
    # Rantai audio: (remix pitch/tempo) → (campur musik latar pelan). => [potongan graph, label/map audio keluaran]
    def audio_graph(has_audio, null_idx, bgm_idx)
      return [ "", has_audio ? "0:a:0" : "#{null_idx}:a" ] unless (@remix && has_audio) || bgm_idx
      src = has_audio ? "[0:a:0]" : "[#{null_idx}:a]"
      steps = []
      if @remix && has_audio
        r = @remix
        steps << "#{src}asetrate=44100*#{r[:pitch]},aresample=44100,atempo=#{format('%.4f', r[:speed] / r[:pitch])}[a0]"
        src = "[a0]"
      end
      if bgm_idx
        steps << "[#{bgm_idx}:a]aformat=sample_rates=44100:channel_layouts=stereo,volume=#{@bgm[:volume]},afade=t=in:d=2[bg]"
        steps << "#{src}aformat=sample_rates=44100:channel_layouts=stereo[a1]"
        steps << "[a1][bg]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]"
      else
        steps[-1] = steps[-1].sub(/\[a0\]\z/, "[a]")
      end
      [ ";" + steps.join(";"), "[a]" ]
    end

    def filter_graph(wm, portrait)
      src = "[0:v]"
      g = +""
      if @remix
        r = @remix
        g << "[0:v]scale=iw*#{r[:zoom]}:ih*#{r[:zoom]},crop=iw/#{r[:zoom]}:ih/#{r[:zoom]}," \
             "eq=brightness=#{r[:bright]}:saturation=#{r[:sat]}:contrast=#{r[:contrast]},hue=h=#{r[:hue]},setpts=PTS/#{r[:speed]}[src];"
        src = "[src]"
      end
      g << if portrait
        "#{src}scale=#{W}:#{H}[base];"
      else
        "#{src}split[s0][s1];[s0]scale=#{W / 4}:#{H / 4}:force_original_aspect_ratio=increase,crop=#{W / 4}:#{H / 4},boxblur=luma_radius=6:luma_power=2,eq=brightness=-0.1,scale=#{W}:#{H}[bg];" \
        "[s1]scale=#{W}:#{H}:force_original_aspect_ratio=decrease[fg];" \
        "[bg][fg]overlay=(W-w)/2:(H-h)/2:format=auto[base];"
      end
      x, y = WM_POS.fetch(@instance.watermark_pos) { WM_POS["top-center"] }
      alpha = (@instance.watermark_alpha / 100.0).clamp(0.1, 1.0)
      if wm
        h = WM_HEIGHT.fetch(@instance.watermark_size_key, 120)
        g + "[1:v]format=rgba,scale=-1:#{h},colorchannelmixer=aa=#{alpha}[wm];[base][wm]overlay=#{x}:#{y}:format=auto[v]"
      else
        text = @instance.display_name.to_s.first(40).gsub(/[\\':%\[\],;]/) { |c| "\\#{c}" }
        # drawtext memakai w/h = ukuran frame dan text_w/text_h = ukuran teks.
        tx = x.sub("(W-w)/2", "(w-text_w)/2").sub("W-w", "w-text_w")
        ty = y.sub("H-h", "h-text_h")
        font = FONT ? "fontfile=#{FONT}:" : ""
        g + "[base]drawtext=#{font}text='#{text}':fontsize=60:fontcolor=white@#{alpha}:borderw=3:bordercolor=black@0.6:x=#{tx}:y=#{ty}[v]"
      end
    end

    # Parameter remix dari seed (deterministik: part 1..n satu episode memakai nilai yang sama).
    def remix_params(seed)
      rnd = Random.new(seed.to_i)
      {
        speed: [ 0.95, 0.96, 0.97, 1.03, 1.04, 1.05 ].sample(random: rnd),
        pitch: [ 0.97, 0.98, 1.02, 1.03 ].sample(random: rnd),
        zoom: (1.03 + rnd.rand * 0.05).round(3),
        hue: rnd.rand(-6..6),
        sat: (0.92 + rnd.rand * 0.16).round(3),
        bright: (rnd.rand * 0.04 - 0.02).round(3),
        contrast: (0.97 + rnd.rand * 0.06).round(3),
        skip: (rnd.rand * 1.2).round(2)
      }
    end

    BGM_DIR = Rails.root.join("storage", "bgm")
    BGM_EXT = %w[mp3 m4a wav ogg flac].freeze
    BGM_FILE_VOLUME = 0.12 # berkas musik biasanya sudah keras → 12 %
    BGM_PAD_VOLUME = 0.10
    # Akord pad sintetis (Hz), dipilih dari seed: Am, C, F, G, Dm, Em
    BGM_CHORDS = [ [ 220, 261.63, 329.63, 440 ], [ 130.81, 164.81, 196, 261.63 ], [ 174.61, 220, 261.63, 349.23 ],
                   [ 196, 246.94, 293.66, 392 ], [ 146.83, 174.61, 220, 293.66 ], [ 164.81, 196, 246.94, 329.63 ] ].freeze

    # Sumber musik latar: berkas di BGM_DIR (deterministik dari seed, di-loop) atau pad sintetis lavfi.
    def bgm_source(seed)
      rnd = Random.new(seed + 7)
      files = BGM_EXT.flat_map { |e| Dir.glob(BGM_DIR.join("*.#{e}").to_s) }.sort
      return { file: files.sample(random: rnd), volume: BGM_FILE_VOLUME } if files.any?
      f = BGM_CHORDS.sample(random: rnd)
      rate = (0.05 + rnd.rand * 0.06).round(3) # ayunan volume pelan 0,05-0,11 Hz
      expr = "(0.55+0.45*sin(2*PI*#{rate}*t))*0.5*(0.5*sin(2*PI*#{f[0]}*t)+0.35*sin(2*PI*#{f[1]}*t)+0.3*sin(2*PI*#{f[2]}*t)+0.2*sin(2*PI*#{f[3]}*t))"
      { lavfi: "aevalsrc=exprs='#{expr}':s=44100,lowpass=f=900,aformat=channel_layouts=stereo", volume: BGM_PAD_VOLUME }
    end

    # Unduh gambar watermark (≤5 MB, ikut redirect); gagal/SVG → nil (fallback teks).
    def fetch_watermark
      src = @instance.watermark_src.to_s
      return nil if src.blank?
      src = "https://#{@instance.primary_host || DEFAULT_HOST}#{src}" if src.start_with?("/")
      uri = URI.parse(src)
      3.times do
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: 20) do |h|
          h.request_get(uri, "User-Agent" => UA, "Accept" => "image/*")
        end
        if res.is_a?(Net::HTTPRedirection) && res["Location"].present?
          uri = URI.join(uri, res["Location"]); next
        end
        return nil unless res.is_a?(Net::HTTPSuccess) && res.body.bytesize.between?(100, 5.megabytes) && !res["Content-Type"].to_s.include?("svg")
        path = File.join(@dir, "wm.img")
        File.binwrite(path, res.body)
        return Array(probe(path, [])["streams"]).any? { |s| s["codec_type"] == "video" } ? path : nil
      end
      nil
    rescue StandardError => e
      Rails.logger.warn("[AutoPoster] watermark #{src}: #{e.class} #{e.message}")
      nil
    end

    def probe(src, opts)
      out = run!([ "ffprobe", "-v", "error", *opts, "-print_format", "json", "-show_streams", "-show_format", src ], timeout: 60)
      JSON.parse(out)
    rescue JSON::ParserError
      raise Error, "ffprobe: keluaran tidak valid"
    end

    def run!(cmd, timeout:)
      out, err, st = Open3.capture3("timeout", timeout.to_s, *cmd)
      raise Error, "#{cmd.first} gagal (#{st.exitstatus}): #{err.to_s.strip.lines.last.to_s.strip.first(200)}" unless st.success?
      out
    end
  end
end
