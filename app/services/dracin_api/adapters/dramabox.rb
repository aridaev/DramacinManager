module DracinApi
  module Adapters
    # https://dramabox.goodbos.online — header x-token
    #   /api/dramabox/trending?lang=   /latest   /foryou
    #   /api/dramabox/dubbed?classify=terbaru|terpopuler&lang=&page=   (15 item/halaman; "terbaru" hanya 1 halaman)
    #   /api/dramabox/search?query=&lang=&page=
    #   /api/dramabox/browse?page=&lang=        → { items, pageNo, hasNext }
    #   /api/dramabox/detail?bookId=
    #   /api/dramabox/allepisode?bookId=        → [ { chapterIndex, chapterName, isLocked, isCharge, videoUrl, videoUrl540/720/1080 } ]
    #
    # Catatan: isLocked/isCharge adalah flag paywall aplikasi DramaBox asli; API tetap mengembalikan videoUrl
    # yang valid (HEAD 200 video/mp4) untuk episode tersebut, jadi flag itu TIDAK dipakai untuk memblokir pemutaran.
    class Dramabox < Base
      default_host "https://dramabox.goodbos.online"

      DUBBED_PAGES = 6
      QUALITY_KEYS = { "videoUrl1080" => "1080p", "videoUrl720" => "720p", "videoUrl540" => "540p" }.freeze

      def home
        trending, latest, dub_new, dub_pop, foryou = concurrently(
          -> { list("/api/dramabox/trending") },
          -> { list("/api/dramabox/latest") },
          -> { dubbed("terbaru", pages: 1) },
          -> { dubbed("terpopuler") },
          -> { list("/api/dramabox/foryou") }
        )
        [
          section(I18n.t("template.v1.sections.trending"), trending),
          section(I18n.t("template.v1.sections.latest"), latest),
          section(I18n.t("template.v1.sections.dubbed_latest"), dub_new),
          section(I18n.t("template.v1.sections.dubbed_popular"), dub_pop),
          section(I18n.t("template.v1.sections.for_you"), foryou)
        ]
      end

      def search(q, page: 1)
        items = Array(get("/api/dramabox/search", query: q, lang: lang, page: page)).map { |d| to_drama(d) }
        page(items, page: page, has_more: items.size >= 10)
      end

      def detail(id) = to_drama(get("/api/dramabox/detail", bookId: id, lang: lang))

      def episodes(id)
        Array(get("/api/dramabox/allepisode", bookId: id)).map do |ep|
          number = ep["chapterIndex"].to_i + 1
          episode(number: number, title: ep["chapterName"].presence || "EP #{number}", locked: video_url(ep).blank?,
                  thumbnail: nil, duration: nil, payload: ep.slice("videoUrl", *QUALITY_KEYS.keys))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        raw = item.payload
        url = video_url(raw)
        return nil if url.blank?
        stream(url: url, episode: ep, sources: sources_from(raw, QUALITY_KEYS))
      end

      private
      def video_url(raw)
        raw["videoUrl720"].presence || raw["videoUrl"].presence || raw["videoUrl540"].presence || raw["videoUrl1080"].presence
      end

      def list(path)
        Array(get(path, lang: lang)).map { |d| to_drama(d) }
      end

      # Semua halaman dubbed diambil paralel; API mengulang halaman terakhir, jadi item duplikat dibuang.
      def dubbed(classify, pages: DUBBED_PAGES)
        batches = concurrently(*(1..pages).map { |pg| -> { Array(get("/api/dramabox/dubbed", classify: classify, lang: lang, page: pg)) } })
        seen = {}
        batches.flatten.filter_map { |d| seen[d["bookId"]] ? nil : (seen[d["bookId"]] = true) && to_drama(d) }
      end

      def to_drama(d)
        drama(id: d["bookId"], title: d["bookName"].to_s.strip, cover: d["coverWap"] || d["cover"], synopsis: d["introduction"],
              genres: Array(d["tags"] || d["tagNames"]).first(5), episodes: d["chapterCount"].to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
