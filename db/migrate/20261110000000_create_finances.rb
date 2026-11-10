class CreateFinances < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    create_table :financial_years do |t|
      t.integer :year, null: false
      t.decimal :opening_balance, precision: 15, scale: 2, null: false, default: 0
      t.references :previous_year, foreign_key: { to_table: :financial_years }
      t.timestamps
    end
    add_index :financial_years, :year, unique: true
    create_table :categories do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :categories, :name, unique: true
    create_table :monthly_limits do |t|
      t.references :financial_year, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.integer :month, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.timestamps
    end
    add_index :monthly_limits, [:financial_year_id, :category_id, :month], unique: true
    create_table :recurring_rules do |t|
      t.references :category, null: false, foreign_key: true
      t.string :description, null: false
      t.string :kind, null: false, default: 'expense'
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.integer :day, null: false, default: 15
      t.date :starts_on, null: false
      t.date :ends_on
      t.string :payment_method
      t.timestamps
    end
    create_table :entries do |t|
      t.references :financial_year, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.references :recurring_rule, foreign_key: { on_delete: :nullify }
      t.date :date, null: false
      t.string :description, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.string :payment_method
      t.text :notes
      t.string :source_key
      t.string :installment_group
      t.integer :installment_number
      t.integer :installments_count
      t.timestamps
    end
    add_index :entries, :source_key, unique: true
    add_index :entries, [:financial_year_id, :date, :status]
    create_table :previews do |t|
      t.references :user, null: false, foreign_key: true
      t.string :purpose, null: false
      t.text :encrypted_payload, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_check_constraint :entries, 'amount > 0', name: 'positive_entry_amount'
    add_check_constraint :entries, "kind IN ('income','expense','benefit_received','benefit_used')", name: 'valid_entry_kind'
    add_check_constraint :entries, "status IN ('planned','actual')", name: 'valid_entry_status'
    add_check_constraint :monthly_limits, 'amount >= 0 AND month BETWEEN 1 AND 12', name: 'valid_monthly_limit'
  end
end
