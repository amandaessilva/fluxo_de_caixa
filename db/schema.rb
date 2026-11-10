# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_10_010000) do
  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "entries", force: :cascade do |t|
    t.integer "financial_year_id", null: false
    t.integer "category_id", null: false
    t.integer "recurring_rule_id"
    t.date "date", null: false
    t.string "description", null: false
    t.string "kind", null: false
    t.string "status", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.string "payment_method"
    t.text "notes"
    t.string "source_key"
    t.string "installment_group"
    t.integer "installment_number"
    t.integer "installments_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "completed_on"
    t.index ["category_id"], name: "index_entries_on_category_id"
    t.index ["financial_year_id", "date", "status"], name: "index_entries_on_financial_year_id_and_date_and_status"
    t.index ["financial_year_id"], name: "index_entries_on_financial_year_id"
    t.index ["recurring_rule_id"], name: "index_entries_on_recurring_rule_id"
    t.index ["source_key"], name: "index_entries_on_source_key", unique: true
    t.check_constraint "amount > 0", name: "positive_entry_amount"
    t.check_constraint "kind IN ('income','expense','benefit_received','benefit_used')", name: "valid_entry_kind"
    t.check_constraint "status IN ('planned','actual')", name: "valid_entry_status"
  end

  create_table "financial_years", force: :cascade do |t|
    t.integer "year", null: false
    t.decimal "opening_balance", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "previous_year_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["previous_year_id"], name: "index_financial_years_on_previous_year_id"
    t.index ["year"], name: "index_financial_years_on_year", unique: true
  end

  create_table "monthly_limits", force: :cascade do |t|
    t.integer "financial_year_id", null: false
    t.integer "category_id", null: false
    t.integer "month", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_monthly_limits_on_category_id"
    t.index ["financial_year_id", "category_id", "month"], name: "idx_on_financial_year_id_category_id_month_0714765d39", unique: true
    t.index ["financial_year_id"], name: "index_monthly_limits_on_financial_year_id"
    t.check_constraint "amount >= 0 AND month BETWEEN 1 AND 12", name: "valid_monthly_limit"
  end

  create_table "previews", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "purpose", null: false
    t.text "encrypted_payload", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_previews_on_user_id"
  end

  create_table "recurring_rules", force: :cascade do |t|
    t.integer "category_id", null: false
    t.string "description", null: false
    t.string "kind", default: "expense", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.integer "day", default: 15, null: false
    t.date "starts_on", null: false
    t.date "ends_on"
    t.string "payment_method"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_recurring_rules_on_category_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "google_calendar_id"
    t.text "google_refresh_token_ciphertext"
    t.text "google_access_token_ciphertext"
    t.datetime "google_access_token_expires_at"
    t.text "google_calendar_sync_error"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "entries", "categories"
  add_foreign_key "entries", "financial_years"
  add_foreign_key "entries", "recurring_rules", on_delete: :nullify
  add_foreign_key "financial_years", "financial_years", column: "previous_year_id"
  add_foreign_key "monthly_limits", "categories"
  add_foreign_key "monthly_limits", "financial_years"
  add_foreign_key "previews", "users"
  add_foreign_key "recurring_rules", "categories"
end
