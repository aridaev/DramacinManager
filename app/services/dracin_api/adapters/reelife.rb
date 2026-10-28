module DracinApi
  module Adapters
    # https://reelife.goodbos.online — katalog pakai header x-token, tetapi play HANYA menerima query ?code=KEY.
    #   /api/v1/home?lang=&page=      → { dramas: [ { bookId, bookName, coverWap, introduction, bookTags, lastChapterId } ], hasMore }
    #   /api/v1/browse?lang=&page=    → sama
    #   /api/v1/search?q=&lang=       → { dramas: [...], hasMore }
    #   /api/v1/book/:id/chapters     → { data: { bookVo: {...}, chapterList: [ { chapterId, chapterName, index, chapterImg, isCharge } ] } }
    #   /api/v1/play/:bookId/:chapterId?code=  → { videoUrl, standbyUrls: [...], thumbnail, title }
    # isCharge=1 untuk semua chapter (flag aplikasi asli), play tetap mengembalikan video (HEAD 200 video/mp4).
    # Host ini lambat (~6 dtk per panggilan), karena itu home dipanggil paralel dan hasil di-cache.
    class Reelife < Base
      default_host "https://reelife.goodbos.online"

      def home
        home, browse = concurrently(-> { list("/api/v1/home") }, -> { list("/api/v1/browse") })
        [
          section(I18n.t("template.v1.sections.for_you"), home),
          section(I18n.t("template.v1.sections.latest"), browse)
        ]
      end

      def search(q, page: 1)
        data = get("/api/v1/search", q: q, lang: lang, page: page)
        page(Array(data["dramas"]).map { |d| to_drama(d) }, page: page, has_more: data["hasMore"] == true)
      end

      def detail(id)
        d = book(id)["bookVo"] || {}
        drama(id: d["bookId"] || id, title: d["bookName"].to_s.strip, cover: d["coverWap"], synopsis: d["introduction"],
              episodes: d["lastChapterId"].to_i.nonzero?, genres: Array(d["bookTags"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(book(id)["chapterList"]).map do |ch|
          number = ch["index"].to_i + 1
          episode(number: number, title: "EP #{number}", thumbnail: ch["chapterImg"], duration: nil, locked: false, payload: ch.slice("chapterId"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        require_key!
        data = Http.get_json("#{host}/api/v1/play/#{id}/#{item.payload['chapterId']}", params: { lang: lang, code: api_key })
        url = data["videoUrl"].presence || Array(data["standbyUrls"]).first
        return nil if url.blank?
        stream(url: url, episode: ep)
      end

      private
      def list(path)
        Array(get(path, lang: lang, page: 1)["dramas"]).map { |d| to_drama(d) }
      end

      def book(id) = get("/api/v1/book/#{id}/chapters", lang: lang)["data"] || {}

      def to_drama(d)
        drama(id: d["bookId"], title: d["bookName"].to_s.strip, cover: d["coverWap"], synopsis: d["introduction"],
              episodes: d["lastChapterId"].to_i.nonzero?, genres: Array(d["bookTags"]).first(5), language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
