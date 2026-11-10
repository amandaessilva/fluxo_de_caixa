# Guia de leitura para quem está aprendendo Rails

## O caminho de uma requisição

Quando você abre `/lancamentos`, `config/routes.rb` escolhe `EntriesController#index`. O controller pede lançamentos ao model `Entry`, que usa Active Record para consultar SQLite. A view `app/views/entries/index.html.erb` transforma o resultado em HTML. O layout acrescenta menu, cabeçalho e mensagens.

Esse é o MVC:

- **Model:** dados, relacionamentos e validações (`app/models`).
- **View:** HTML com Ruby entre `<%= ... %>` (`app/views`).
- **Controller:** recebe parâmetros e coordena a resposta (`app/controllers`).

As regras que envolvem vários modelos ficam em `app/services`, para não sobrecarregar controllers ou views. Rails carrega as classes pelo nome dos arquivos: `balance_report.rb` define `BalanceReport`.

## Modelos

| Classe | Responsabilidade |
| --- | --- |
| `User` | Conta pessoal e hash BCrypt da senha |
| `FinancialYear` | Ano, saldo inicial e vínculo opcional com ano anterior |
| `Category` | Grupo global, reutilizado entre anos |
| `MonthlyLimit` | Limite de uma categoria em um mês e ano; combinação única |
| `Entry` | Lançamento com data, tipo, situação, valor, pagamento e observações |
| `RecurringRule` | Regra mensal que materializa previsões, sem duplicar a mesma origem |
| `Preview` | Dados normalizados criptografados para confirmação, com expiração |

`belongs_to` significa que o registro referencia outro. `has_many` permite acessar uma coleção. Uma migration define as tabelas e índices; o arquivo `db/schema.rb` representa o resultado. Não edite uma migration já aplicada em produção: crie uma nova.

O domínio usa nomes em inglês por convenção Rails; os textos exibidos são em português. `Entry::KINDS` e `Entry::STATUSES` centralizam códigos e rótulos. `rails-i18n` fornece mensagens e datas pt-BR; `config/locales/pt-BR.yml` traduz os nomes dos campos.

## Onde alterar cada regra

- Saldo e gastos por categoria: `BalanceReport`.
- Criação e herança dos anos: `YearBuilder`.
- Divisão exata do total e vencimentos: `InstallmentBuilder`.
- Contas mensais e chaves de idempotência: `RecurringRule#materialize!`.
- Mapeamento XLSX e conferência: `XlsxImporter`.
- Esquema JSON e restauração: `BackupService`.
- Validação de centavos: concern `MonetaryPrecision`.

`transaction do ... end` significa “ou tudo é salvo, ou nada é salvo”. Métodos com `!`, como `create!`, levantam uma exceção se houver erro; isso faz a transação voltar ao estado anterior. Os testes de rollback verificam que nem anos nem categorias ficam parcialmente criados.

## Dinheiro

Não use `Float`, `to_f` ou somas com `0.0` para cálculos financeiros. Use `BigDecimal('12.34')`. O formulário aceita `1234,56` e `1.234,56`; internamente o decimal usa ponto. A formatação BRL ocorre apenas na view, usando `brl(...)`.

SQLite tem afinidade numérica, e seu `SUM` pode usar ponto flutuante. Por isso `BalanceReport` lê valores tipados pelo Active Record e soma no Ruby. O importador usa Roo para ler a planilha e XML para preservar números originais e detectar fórmulas sem cache.

## Hotwire sem Node

Importmap entrega os módulos JavaScript locais das gems. Turbo acelera navegação e submissão dos formulários sem exigir React. Stimulus cuida do menu móvel e da explicação do parcelamento. Os controllers estão em `app/javascript/controllers`. Não precisa instalar npm nem executar um bundler JavaScript.

Formulários usam `form_with`; erros respondem com HTTP 422 e operações de exclusão usam redirecionamento 303. O token CSRF é incluído pelo Rails. JavaScript não decide saldos, validações nem permissões: essas regras estão no servidor.

## Como evoluir com segurança

1. Escreva um teste para a regra desejada em `test/models` ou um fluxo HTTP em `test/integration`.
2. Execute `bin/rails test caminho/do/teste.rb`.
3. Faça a menor alteração coerente no serviço/model/controller responsável.
4. Execute `bin/rails test` e `bin/rails zeitwerk:check`.
5. Antes de mudar dados reais, exporte um backup e teste a migration numa cópia do banco.

Exemplo de leitura no console (somente depois de criar dados pela interface):

```ruby
year = FinancialYear.find_by!(year: 2026)
report = BalanceReport.new(year, status: 'actual', month: 11)
report.closing_balance
```

A aplicação não tem jobs permanentes: previsões são geradas no cadastro da regra e na criação de anos. Limpeza de prévias é uma tarefa de manutenção. Melhorias possíveis incluem edição de séries, conciliação, importação assistida dos lançamentos avulsos das abas auxiliares e suporte multiusuário com escopo explícito em todos os registros.
