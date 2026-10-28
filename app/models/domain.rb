# Domain kustom untuk instance. Saat dibuat, zone Cloudflare dibuat otomatis (Domain#provision!),
# nameserver CF disimpan agar user mengarahkan NS domainnya ke sana; SSL Flexible dan record A/CNAME ke IP VPS diset.
class Domain < ApplicationRecord
  HOSTNAME_RE = /\A(?=.{4,253}\z)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/

  enum :status, { pending_ns: 0, active: 1, error: 2, removed: 3 }, default: :pending_ns

  belongs_to :instance

  validates :hostname, presence: true, uniqueness: true, format: { with: HOSTNAME_RE, message: "bukan nama domain yang valid" }
  before_validation { self.hostname = hostname.to_s.strip.downcase.sub(%r{\Ahttps?://}, "").sub(/\Awww\./, "").sub(%r{/.*\z}, "") }

  scope :ordered, -> { order(created_at: :desc) }
  scope :servable, -> { where(status: [ statuses[:active], statuses[:pending_ns] ]) }

  after_commit :sync_edge, on: [ :create, :update, :destroy ]

  def self.find_for_host(host)
    h = host.to_s.downcase.sub(/\Awww\./, "")
    servable.find_by(hostname: h)
  end

  def nameservers = Array(cf_nameservers)

  # Perbarui daftar server_name Nginx + cache host→instance setiap domain berubah.
  def sync_edge
    InstanceHost.forget(hostname)
    NginxDomains.sync!
  rescue StandardError => e
    Rails.logger.warn("[Domain] sync_edge #{hostname}: #{e.class} #{e.message}")
  end

  # Buat zone + SSL + DNS. Idempoten: aman dipanggil ulang (mis. tombol "Coba lagi").
  def provision!(client = CloudflareClient.from_settings)
    ip = Setting.vps_ip
    raise CloudflareClient::Error, "IP VPS belum diisi di Pengaturan Situs" if ip.blank?
    zone = client.create_zone(hostname)
    update!(cf_zone_id: zone["id"], cf_nameservers: Array(zone["name_servers"]), cf_status: zone["status"], last_error: nil, last_checked_at: Time.current)
    client.set_ssl_mode(zone["id"], Setting.cloudflare_ssl_mode)
    client.set_always_https(zone["id"], on: true)
    client.upsert_dns(zone["id"], type: "A", name: "@", content: ip, proxied: true)
    client.upsert_dns(zone["id"], type: "CNAME", name: "www", content: hostname, proxied: true)
    refresh_status!(client, zone: zone)
    self
  rescue CloudflareClient::Error => e
    update_columns(status: Domain.statuses[:error], last_error: e.message.truncate(500), last_checked_at: Time.current)
    raise
  end

  # Cek apakah NS sudah diarahkan (zone status "active" di CF).
  def refresh_status!(client = CloudflareClient.from_settings, zone: nil)
    return self if cf_zone_id.blank?
    zone ||= client.zone(cf_zone_id)
    now_active = zone["status"] == "active"
    update!(cf_status: zone["status"], cf_nameservers: Array(zone["name_servers"]).presence || cf_nameservers,
            status: now_active ? :active : :pending_ns, activated_at: (now_active ? (activated_at || Time.current) : nil),
            last_checked_at: Time.current, last_error: nil)
    self
  rescue CloudflareClient::Error => e
    update_columns(last_error: e.message.truncate(500), last_checked_at: Time.current)
    self
  end

  # Hapus zone di CF (opsional) lalu record lokal.
  def deprovision!(client = CloudflareClient.from_settings, delete_zone: true)
    client.delete_zone(cf_zone_id) if delete_zone && cf_zone_id.present? && client.configured?
  rescue CloudflareClient::Error
    nil
  ensure
    destroy
  end
end
