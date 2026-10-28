module DracinApi
  module Adapters
    # https://reelshort.goodbos.online — auth ?code=KEY (x-token juga diterima); path TANPA prefix /api; lang `id`→`in`
    #   /home?tab=&lang=          → { books: [ { id, title, pic, chapters } ], tabs: [...] }   (tab: default | ranking)
    #   /trending?lang=           → { popular: [...], tags: [...] }
    #   /search?q=&lang=          → { results: [...], page }
    #   /detail/:id?lang=         → { id, title, pic, desc, chapters, theme: [], views }
    #   /chapters/:id?lang=       → { chapters: [ { id, name, duration, is_lock } ] }
    #   /allepisodes/:id?lang=    → { episodes: [ { episode, id, name, duration, streams: [ { quality: "720p"|"540p"|"0p", url } ] } ] }
    class Reelshort < Base
      default_host "https://reelshort.goodbos.online"
      LANG_MAP = { "id" => "in" }.freeze

      def home
        home, ranking, trending = concurrently(-> { get("/home", lang: lang) }, -> { get("/home", tab: "ranking", lang: lang) }, -> { get("/trending", lang: lang) })
        [
          section(I18n.t("template.v1.sections.for_you"), books(home["books"])),
          section(I18n.t("template.v1.sections.trending"), books(trending["popular"])),
          section(I18n.t("template.v1.sections.ranking", default: "Peringkat"), books(ranking["books"]))
        ]
      end

      def search(q, page: 1)
        page(books(get("/search", q: q, lang: lang)["results"]), page: 1, has_more: false)
      end

      def detail(id)
        d = get("/detail/#{id}", lang: lang)
        drama(id: d["id"] || id, title: d["title"].to_s.strip, cover: d["pic"], synopsis: d["desc"], genres: Array(d["theme"]).first(5),
              episodes: d["chapters"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(get("/allepisodes/#{id}", lang: lang)["episodes"]).map do |e|
          streams = Array(e["streams"]).select { |s| s["url"].present? }
          episode(number: e["episode"], title: e["name"].presence || "EP #{e['episode']}", thumbnail: nil, duration: seconds_to_clock(e["duration"]),
                  locked: streams.empty?, payload: { "streams" => streams })
        end
      end

      # Tiap kualitas hadir dua versi: HEVC (path .../video/...-video-sd.m3u8, codec hvc1) dan H.264 (path /vod-.../...-ld.m3u8).
      # Browser desktop umumnya tidak bisa decode HEVC (hanya suara), jadi pilih H.264; HEVC hanya fallback.
      def play(id, ep)
        item = find_episode(id, ep) or return nil
        streams = Array(item.payload["streams"]).reject { |s| s["quality"].to_s.to_i.zero? } # buang master "0p" (variannya HEVC)
        return nil if streams.empty?
        h264 = streams.select { |s| h264?(s["url"]) }
        pool = h264.any? ? h264 : streams
        sorted = pool.sort_by { |s| -s["quality"].to_s.to_i }
        best = sorted.find { |s| s["quality"].to_s.to_i == 720 } || sorted.first
        sources = sorted.map { |s| { label: s["quality"].to_s.downcase, url: s["url"] } }.uniq { |s| s[:label] }
        stream(url: best["url"], episode: ep, sources: sources)
      end

      def h264?(url) = url.to_s.include?("/vod-") || url.to_s.match?(/-(?:ld|sd|hd)\.m3u8\z/) && !url.to_s.include?("-video-")

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def books(list)
        Array(list).map do |b|
          drama(id: b["id"], title: b["title"].to_s.strip, cover: b["pic"], synopsis: b["desc"], genres: Array(b["theme"]).first(5),
                episodes: b["chapters"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
        end
      end
    end
  end
end
