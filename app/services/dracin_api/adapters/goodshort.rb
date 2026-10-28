module DracinApi
  module Adapters
    # https://goodshort.goodbos.online — path TANPA /api; auth ?code=KEY; lang `id`→`in`; rate limit 60 req/menit per code (ban 2 menit)
    #   /home?lang=&page=      → { data: { records: [ { columnId, name, items: [ { bookId, bookName, cover, chapterCount, introduction, labels } ] } ], pages } }
    #   /hot?lang=             → { data: [ { action (bookId), tags (judul) } ] }
    #   /search?lang=&q=&page=&size=  → { data: { searchResult: { records: [...] } } }  (q minimal 2 kata)
    #   /book/:id?lang=        → { data: { book: { bookId, bookName, cover, introduction, chapterCount, labels } } }
    #   /batchload/:id?lang=   → { data: { episodes: [ { chapterName, index, price, image, videos: [ { type: "720p", filePath (HLS via host DracinAPI) } ] } ] } }
    class Goodshort < Base
      default_host "https://goodshort.goodbos.online"
      LANG_MAP = { "id" => "in" }.freeze

      def home
        data = get("/home", lang: lang)["data"] || {}
        items_by_col = Array(data["records"]).each_with_object([]) do |r, acc|
          items = Array(r["items"]).select { |i| i["bookId"].present? }.map { |i| to_drama(i) }
          next if items.empty?
          name = r["name"].to_s.strip
          if name.present? && items.size > 1
            acc << section(name, items)
          else
            (acc.find { |s| s.title == I18n.t("template.v1.sections.for_you") } || (acc << section(I18n.t("template.v1.sections.for_you"), [])).last).items.concat(items)
          end
        end
        items_by_col.map { |s| section(s.title, s.items.uniq(&:id)) }.reject { |s| s.items.empty? }
      end

      def search(q, page: 1)
        q = "#{q} drama" if q.to_s.split.size < 2
        recs = Array(get("/search", lang: lang, q: q, page: page, size: 20).dig("data", "searchResult", "records"))
        page(recs.map { |r| to_drama(r) }, page: page, has_more: false)
      end

      def detail(id)
        b = get("/book/#{id}", lang: lang).dig("data", "book") || {}
        to_drama(b.merge("bookId" => b["bookId"] || id))
      end

      def episodes(id)
        Array(get("/batchload/#{id}", lang: lang).dig("data", "episodes")).map do |e|
          n = e["index"].to_i + 1
          vids = Array(e["videos"]).select { |v| v["filePath"].present? }
          episode(number: n, title: "EP #{n}", thumbnail: e["image"], duration: nil, locked: vids.empty?, payload: { "videos" => vids })
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        vids = Array(item.payload["videos"]).sort_by { |v| -v["type"].to_s.to_i }
        return nil if vids.empty?
        best = vids.find { |v| v["type"].to_s.to_i == 720 } || vids.first
        sources = vids.map { |v| { label: v["type"].to_s.downcase, url: with_code(v["filePath"]) } }
        stream(url: with_code(best["filePath"]), episode: ep, sources: sources)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def with_code(url) = url.include?("?") ? "#{url}&code=#{api_key}" : "#{url}?code=#{api_key}"

      def to_drama(b)
        tags = Array(b["labels"].presence || b["tagNames"] || b["tags"]).map { |t| t.is_a?(Hash) ? (t["name"] || t["label"]) : t }.compact
        drama(id: b["bookId"] || b["id"], title: b["bookName"].to_s.strip, cover: b["cover"] || b["bookDetailCover"] || b["image"], synopsis: b["introduction"],
              genres: tags.first(5), episodes: b["chapterCount"].to_i.nonzero?, language: nil, rating: b["ratings"].presence, year: nil, status: nil)
      end
    end
  end
end
