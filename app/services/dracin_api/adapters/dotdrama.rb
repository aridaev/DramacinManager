module DracinApi
  module Adapters
    # https://dotdrama.goodbos.online — token lewat query ?code=
    #   /api/drama/list?lang=&page=&limit=  → { d…: { l…: [drama], p…: page, p…: limit, t…: total, t…: pages } }
    #   /api/search?q=&lang=                → { results: [drama], total }
    #   /api/drama/:id                      → { d…: { b…: drama, e…: [ { e…: nomor, p…: [ { B…: url, D…: "540P", D…: durasi } ] } ] } }
    #   /api/drama/:id/:ep                  → { drama_id, episode, total_episodes, video_hd, video_url }
    #
    # Nama kunci di list/detail diacak per host (RapidTV memakai skema yang sama dengan kunci lain), tetapi huruf
    # pertama kunci selalu sama dengan huruf pertama nama field aslinya, jadi field dicari dari awalan + bentuk nilai.
    class Dotdrama < Base
      default_host "https://dotdrama.goodbos.online"
      LIMIT = 18

      def home
        data = get("/api/drama/list", lang: lang, page: 1, limit: LIMIT)
        items = list_in(data).map { |d| to_drama(d) }
        [ section(I18n.t("template.v1.sections.for_you"), items) ]
      end

      def search(q, page: 1)
        return page([], page: page, has_more: false) if page.to_i > 1
        data = get("/api/search", q: q, lang: lang)
        page(list_in(data).map { |d| to_drama(d) }, page: page, has_more: false)
      end

      def detail(id)
        root = hash_in(get("/api/drama/#{id}", lang: lang))
        info = root.values.find { |v| v.is_a?(Hash) } || root
        to_drama(info, id)
      end

      def episodes(id)
        root = hash_in(get("/api/drama/#{id}", lang: lang))
        list = root.values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) } || []
        list.map do |e|
          num = field(e, "e", Integer) { |v| v.between?(1, 5000) }
          plays = e.values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) } || []
          dur = plays.filter_map { |p| p.values.find { |v| v.is_a?(Numeric) && !v.is_a?(Integer) } }.first
          episode(number: num, title: "EP #{num}", thumbnail: nil, duration: seconds_to_clock(dur&.round), locked: false, payload: { "plays" => plays })
        end.select { |e| e.number.positive? }.sort_by(&:number)
      end

      def play(id, ep)
        v = get("/api/drama/#{id}/#{ep}", lang: lang)
        sources = sources_from(v, { "video_hd" => "HD", "video_url" => "SD" })
        if sources.empty?
          plays = v["data"].is_a?(Hash) ? v["data"].values.find { |x| x.is_a?(Array) && x.first.is_a?(Hash) } : nil
          plays ||= find_episode(id, ep)&.payload&.dig("plays")
          sources = sources_from_plays(plays)
        end
        return nil if sources.empty?
        stream(url: sources.first[:url], episode: ep, sources: sources)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      # Varian kualitas: [ { B…: url, D…: "540P", D…: durasi, W…: lebar } ] → urut dari resolusi tertinggi.
      def sources_from_plays(plays)
        Array(plays).filter_map do |p|
          next unless p.is_a?(Hash)
          url = p.values.find { |x| x.is_a?(String) && x.start_with?("http") }
          label = p.values.find { |x| x.is_a?(String) && x.match?(/\A\d{3,4}p\z/i) }
          url ? { label: label.to_s.upcase.presence || "Auto", url: url } : nil
        end.sort_by { |s| -s[:label].to_i }
      end

      # Hash berisi data utama: pertama cari nilai Hash (list/detail), kalau tidak ada pakai root (search).
      def hash_in(data)
        return {} unless data.is_a?(Hash)
        data.values.find { |v| v.is_a?(Hash) } || data
      end

      def list_in(data)
        h = hash_in(data)
        h.values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) } || []
      end

      # Ambil nilai dari kunci berawalan `prefix` dengan bentuk nilai `type` (dan filter tambahan).
      def field(h, prefix, type = String, &ok)
        return nil unless h.is_a?(Hash)
        h.each { |k, v| return v if k.to_s.downcase.start_with?(prefix) && v.is_a?(type) && (ok.nil? || ok.call(v)) }
        nil
      end

      # ID yang dipakai endpoint detail/play: DotDrama memakai id panjang (19 digit).
      def id_of(d)
        field(d, "d") { |v| v.match?(/\A\d{10,}\z/) }
      end

      def to_drama(d, fallback_id = nil)
        id = id_of(d) || fallback_id
        drama(id: id, title: field(d, "n").presence || "—", cover: field(d, "p") { |v| v.start_with?("http") },
              synopsis: field(d, "d") { |v| !v.match?(/\A\d+\z/) }, episodes: field(d, "e", Integer) { |v| v.between?(1, 5000) }.to_i.nonzero?,
              language: field(d, "l") { |v| v.length <= 5 }, rating: nil, year: nil, status: nil)
      end
    end
  end
end
