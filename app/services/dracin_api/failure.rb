module DracinApi
  # Mengelompokkan error penyedia menjadi jenis yang bisa dijelaskan ke pengunjung (halaman status) dan admin (tabel kesehatan).
  # Menerima objek error atau teks `Provider#last_error` ("HttpError: HTTP 525").
  module Failure
    KINDS = %i[maintenance down auth rate_limit timeout not_found generic].freeze
    DOWN_CODES = [ 502, 503, 504, 520, 521, 522, 523, 524, 525, 526 ].freeze

    module_function

    def kind(error_or_message)
      msg = error_or_message.respond_to?(:message) ? error_or_message.message.to_s : error_or_message.to_s
      code = error_or_message.respond_to?(:code) ? error_or_message.code.to_i : 0
      code = msg[/HTTP (\d{3})/, 1].to_i if code.zero?

      return :maintenance if msg.match?(/maintenance|undergoing|unreachable|perbaikan/i)
      return :rate_limit if code == 429 || msg.match?(/rate.?limit|too many request/i)
      return :auth if [ 401, 403 ].include?(code) || msg.match?(Health::AUTH_RE)
      return :timeout if msg.match?(/timeout|timed out|waktu tunggu/i)
      return :down if DOWN_CODES.include?(code) || msg.match?(/koneksi|connection|tidak merespons|ssl/i)
      return :not_found if [ 404, 410 ].include?(code) || msg.match?(/not found|tidak ditemukan|invalid .*id|program not found/i)
      :generic
    end
  end
end
