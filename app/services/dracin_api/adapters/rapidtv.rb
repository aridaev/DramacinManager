module DracinApi
  module Adapters
    # https://rapidtv.goodbos.online — skema sama persis dengan DotDrama (kunci acak), bedanya endpoint
    # detail/play memakai id pendek (field s… = "90247"), bukan id 19 digit.
    class Rapidtv < Dotdrama
      default_host "https://rapidtv.goodbos.online"

      private
      def id_of(d)
        field(d, "s") { |v| v.match?(/\A\d{3,9}\z/) } || super
      end
    end
  end
end
