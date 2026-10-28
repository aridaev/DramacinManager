class User < ApplicationRecord
  enum :role, { user: 0, admin: 1 }, default: :user
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable
end
