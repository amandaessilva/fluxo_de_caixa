ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'caxlsx'

class ActiveSupport::TestCase
  def setup_finances
    @year = FinancialYear.create!(year: 2026, opening_balance: '100.00')
    @category = Category.create!(name: 'Teste sintético')
  end
  def entry(overrides = {})
    @year.entries.create!({ category: @category, date: Date.new(2026,1,15), description: 'Teste', kind: 'expense', status: 'actual', amount: '10.00' }.merge(overrides))
  end
  def workbook(months: ['Janeiro'], invalid: false, auxiliary: false, year: 2026)
    file = Tempfile.new(['synthetic', '.xlsx'])
    Axlsx::Package.new do |package|
      months.each_with_index do |name, index|
        package.workbook.add_worksheet(name: name) do |sheet|
          (1..211).each do |row|
            cells = []
            cells[0] = "Ano #{year}" if row == 1 && year
            if [5, 131].include?(row)
              cells = ['Data', 'Descrição', 'Pagamento', 'Grupo', 'Observações', 'Juros', 'Entrada', 'Benefício recebido', 'Benefício utilizado', 'Saída', 'Saldo', nil, 'Grupo', 'Limite']
            elsif row == 6
              cells = [nil, 'Linha de teste', 'Pix', 'Teste sintético', 'Observação', 0.01, invalid ? 'inválido' : 100, 50, 20, 30, '=SUM(G6:H6)-SUM(I6:J6)', nil, 'Teste sintético', 200 + index]
            elsif row == 132
              cells = [Date.new(year || 2026,index+1,2), 'Previsão de teste', nil, 'Teste sintético', nil, nil, 80, nil, nil, 15]
            end
            sheet.add_row(cells, escape_formulas: false)
          end
        end
      end
      if auxiliary
        package.workbook.add_worksheet(name: 'Parcelas') do |sheet|
          sheet.add_row ['Descrição', 'Quantidade', 'Valor']
          sheet.add_row ['Dado sintético', 10, 20]
          sheet.add_row ['Total', nil, '=SUM(C2:C2)'], escape_formulas: false
        end
      end
      package.serialize(file.path)
    end
    file
  end
  def preview(file)
    XlsxImporter.new(file.path, filename: 'teste.xlsx', fallback_year: 2026).preview
  end
end

class ActionDispatch::IntegrationTest
  def sign_in
    @user = User.create!(email: 'teste@example.com', password: 'senha-sintetica-segura')
    post session_path, params: { email: @user.email, password: 'senha-sintetica-segura' }
    assert_redirected_to root_path
  end
end
