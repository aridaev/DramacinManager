module DracinApi
  module Adapters
    # Kontrak adapter: home / search / detail / episodes / play → struct DracinApi::Catalog.
    class Base
      attr_reader :provider, :api_key, :lang

      # Host default jika /api/status belum pernah disinkronkan (field `api`).
      def self.default_host(host = nil)
        @default_host = host if host
        @default_host
      end

      # Pemetaan kode bahasa aplikasi → kode yang dipahami provider (override per adapter bila beda).
      LANG_MAP = {}.freeze

      def initialize(provider, api_key:, lang: nil)
        @provider = provider
        @api_key = api_key.presence
        code = lang.presence || "en"
        @lang = self.class::LANG_MAP.fetch(code, code)
      end

      def slug = provider.slug

      def host
        @host ||= begin
          url = provider.api_url.presence || self.class.default_host
          raise Unsupported, I18n.t("dracin_api.errors.no_host", provider: provider.name) if url.blank?
          URI.parse(url).then { |u| "#{u.scheme}://#{u.host}" }
        end
      end

      def home            = raise(NotImplementedError)
      def search(_q, page: 1) = raise(NotImplementedError)
      def detail(_id)     = raise(NotImplementedError)
      def episodes(_id)   = raise(NotImplementedError)
      def play(_id, _ep)  = raise(NotImplementedError)

      # Daftar episode yang sudah ada di cache Catalog bisa disuntikkan agar play tidak mengambil ulang.
      def prime_episodes(id, list)
        (@episode_lists ||= {})[id.to_s] = Array(list)
      end

      private
      def require_key!
        raise MissingApiKey, I18n.t("dracin_api.errors.missing_api_key") unless api_key
      end

      # Default: token lewat header x-token (DramaBox, Vibeshort, DramaWave, ...).
      def get(path, params = {})
        require_key!
        memo(path, params) do
          case provider.effective_auth_mode
          when "query_code" then Http.get_json("#{host}#{path}", params: params.merge(code: api_key))
          when "query_key"  then Http.get_json("#{host}#{path}", params: params.merge(key: api_key))
          when "bearer"     then Http.get_json("#{host}#{path}", params: params, headers: { "Authorization" => "Bearer #{api_key}" })
          when "none"       then Http.get_json("#{host}#{path}", params: params)
          else Http.get_json("#{host}#{path}", params: params, headers: { "x-token" => api_key })
          end
        end
      end

      # Satu instance adapter hidup selama satu request; detail/episodes/play sering memukul endpoint yang sama,
      # jadi respons JSON diingat per (path, params) agar tidak ada HTTP ganda ke host yang lambat.
      def memo(path, params)
        @memo ||= {}
        key = [ path, params.to_a.sort_by { |k, _| k.to_s } ]
        return @memo[key] if @memo.key?(key)
        @memo[key] = yield
      end


      def find_episode(id, ep)
        list = (@episode_lists ||= {})[id.to_s] ||= Array(episodes(id))
        list.find { |e| e.number == ep.to_i }
      end

      # Menjalankan beberapa panggilan API sekaligus (I/O-bound). Hasil dikembalikan sesuai urutan blok;
      # error dari salah satu blok dilempar ulang di thread pemanggil.
      def concurrently(*tasks)
        return tasks.map(&:call) if tasks.size <= 1
        tasks.map { |t| Thread.new { Rails.application.executor.wrap { t.call } } }.map(&:value)
      end

      def drama(id:, title:, **attrs)
        Catalog::Drama.new(provider: slug, id: id.to_s, title: title.to_s, genres: [], **attrs)
      end

      def episode(number:, **attrs)
        Catalog::Episode.new(number: number.to_i, locked: false, **attrs)
      end

      # sources: [ { label:, url: } ] semua varian kualitas; url = varian yang diputar pertama kali.
      # proxied: true bila CDN provider tidak kirim CORS / menolak Referer (HLS lewat proxy server).
      def stream(url:, episode:, sources: nil, quality: nil, **attrs)
        srcs = Array(sources).map { |s| { label: s[:label].to_s, url: s[:url].to_s } }.reject { |s| s[:url].blank? }.uniq { |s| s[:url] }
        srcs = [ { label: "Auto", url: url.to_s } ] if srcs.empty?
        Catalog::Stream.new(url: url, episode: episode.to_i, format: attrs.delete(:format) || (url.to_s.match?(%r{\.m3u8|/hls/|m3u8}) ? "HLS" : "MP4"),
                            quality: quality || srcs.map { |s| s[:label] }.reject { |l| l == "Auto" }, sources: srcs,
                            subtitles: [], cookies: nil, proxied: false, **attrs)
      end

      # Membangun daftar sumber dari hash API: keys = { "videoUrl1080" => "1080p", ... } (urutan = prioritas).
      def sources_from(raw, keys)
        keys.filter_map { |k, label| raw[k].present? ? { label: label, url: raw[k] } : nil }
      end

      # Subtitle: { lang:, label:, url: } — lang dua huruf agar cocok dengan I18n.locale.
      def subtitle(lang:, url:, label: nil)
        code = lang.to_s.downcase.split(/[-_]/).first.presence || self.lang.to_s.split(/[-_]/).first.presence || "und"
        { lang: code, label: label.presence || (code == "und" ? "Subtitle" : code.upcase), url: url.to_s }
      end

      def page(items, page:, has_more:)
        Catalog::Page.new(items: items, page: page.to_i, has_more: has_more ? true : false)
      end

      def section(title, items)
        Catalog::Section.new(title: title, items: items)
      end

      def seconds_to_clock(sec)
        return nil if sec.blank?
        s = sec.to_i
        format("%d:%02d", s / 60, s % 60)
      end
    end
  end
end
