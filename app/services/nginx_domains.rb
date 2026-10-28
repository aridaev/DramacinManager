# Menulis daftar host domain instance ke file yang di-include server block Nginx "dracin-instances",
# lalu reload Nginx. Dipanggil dari callback Domain (Puma berjalan sebagai root).
class NginxDomains
  CONF = "/etc/nginx/dracin_domains.conf".freeze
  PLACEHOLDER = "dracin-instances.invalid".freeze

  def self.sync!
    return false unless File.directory?(File.dirname(CONF))
    hosts = Domain.where.not(status: :removed).order(:hostname).pluck(:hostname).flat_map { |h| [ h, "www.#{h}" ] }
    content = "# Dibuat otomatis oleh DracinManager (tabel domains) — jangan diedit manual.\nserver_name #{[ PLACEHOLDER, *hosts ].join(' ')};\n"
    return false if File.exist?(CONF) && File.read(CONF) == content
    File.write(CONF, content)
    reload!
  end

  def self.reload!
    return false unless system("nginx", "-t", "-q", out: File::NULL, err: File::NULL)
    system("systemctl", "reload", "nginx", out: File::NULL, err: File::NULL)
  end
end
