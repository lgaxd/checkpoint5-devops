# Roteiro de gravação — DimDim no Azure

Roteiro pronto para gravar a demonstração do checkpoint. Duração prevista: **8 a 10 minutos de apresentação**, além do tempo variável de provisionamento e inicialização Azure. Grave em 720p ou superior, com áudio claro. A interface pode estar em português e os nomes dos recursos devem corresponder ao `.env`.

> **Importante:** os recursos Azure foram removidos após a validação. Para uma demonstração ao vivo, reprovisione antes de gravar e faça o teardown somente depois de guardar o vídeo e as evidências. Não mostre o `.env`, senhas, tokens JWT, valores de connection string nem comandos que revelem segredos. Não use `set -x`.

## Antes de apertar Gravar

1. Confira no `.env` a região autorizada **Chile Central (`chilecentral`)**, nomes de recursos, `CLIENT_IP` público atual e credenciais, sem compartilhar o arquivo.
2. No WSL, entre na pasta do projeto, confirme a subscription Azure e as ferramentas. Se necessário, ative o caminho do `sqlcmd`:

   ```bash
   cd /mnt/c/Users/LGA/Documents/checkpoint5-devops/cp4-devops
   export PATH="$PATH:/opt/mssql-tools18/bin"
   az account show --output table
   java -version
   command -v az sqlcmd curl zip
   ```

3. Confirme que está selecionada a subscription correta. O `.env` deve estar salvo e acessível ao WSL.
4. Rode os testes antes da gravação, para não consumir tempo de vídeo com falhas:

   ```bash
   ./mvnw --batch-mode clean test
   ```

   A última validação executada passou com **3 testes, zero falhas**. Se quiser mostrar essa etapa, mantenha a janela de terminal aberta no resumo do Maven, sem imprimir nem exportar segredos.
5. Prepare no navegador as páginas do portal Azure, mas não deixe visível nenhum segredo:
   - Resource Group: `561413-dimdim-rg`
   - App Service: `561413-dimdim-webapp`
   - Azure SQL Database: `db-dimdim`
   - Application Insights: `561413-dimdim-insights`
   - Região: Chile Central
6. Planeje iniciar o provisionamento pouco antes de gravar. O deploy pode demorar vários minutos; a duração depende do Azure. Se a gravação não puder incluir a espera, mostre o terminal com o deploy já concluído e explique que esse foi o comando usado.

## Linha do tempo e fala sugerida

| Minutagem | O que mostrar | Fala sugerida |
|---|---|---|
| **00:00–00:35** | Abra o navegador na página inicial do projeto ou no README. Mostre o nome DimDim e a arquitetura/resumo, sem exibir o `.env`. | “Este é o DimDim, uma aplicação Java 21 para cadastro de usuários e fazendas. A aplicação roda no Azure App Service, persiste os dados no Azure SQL e envia telemetria ao Application Insights.” |
| **00:35–01:10** | Mostre brevemente a estrutura do projeto no VS Code: `src/main/java/br/com/fiap/dimdim`, `scripts/`, `docs/architecture.md` e exemplos em `docs/api/`. Não abra arquivos de configuração que contenham valores sensíveis. | “O código está organizado em camadas: controllers, services, repositories e entidades. Também estão incluídos o DDL, os scripts Azure, os testes e os exemplos da API. A solução não usa Docker, ACI, ACR nem GitHub Actions.” |
| **01:10–01:40** | Mostre o resumo dos testes Maven já executados, ou rode `./mvnw --batch-mode clean test` se o tempo permitir. | “Antes da publicação, os testes de integração verificam autenticação, validação, CRUD e o relacionamento entre usuário e fazenda. Os testes usam H2; a execução Azure usa Azure SQL.” |
| **01:40–02:10** | No WSL, mostre apenas a subscription ativa e a região configurada, sem abrir `.env`. Inicie `bash scripts/azure-deploy.sh`. | “O deploy é feito pela Azure CLI. O script cria ou reutiliza os recursos previstos, inicializa as duas tabelas e o usuário SQL restrito, configura os App Settings e publica o JAR com `az webapp deploy`.” |
| **02:10–02:35** | Mostre a saída do deploy quando indicar publicação concluída e health check aprovado. Não mostre valores de credenciais, tokens ou connection strings. | “O pacote inclui o Java Agent do Application Insights. O health check final valida que a aplicação está saudável e que consegue acessar o datasource SQL.” |
| **02:35–03:05** | No portal Azure, mostre o Resource Group e sua lista de recursos; em seguida abra o App Service e mostre status Running e região. | “Aqui estão os recursos do projeto na região permitida pela subscription: o App Service Linux com Java 21, a base Azure SQL e o Application Insights.” |
| **03:05–03:35** | Abra `https://561413-dimdim-webapp.azurewebsites.net/`. Mostre a tela inicial e depois `https://561413-dimdim-webapp.azurewebsites.net/actuator/health`, com status `UP`. | “A interface web e a API são servidas pelo mesmo App Service. O health check retorna UP e confirma a prontidão da aplicação e do banco.” |
| **03:35–04:10** | Na interface, escolha **Criar conta**. Use dados fictícios (por exemplo, nome “Responsável Demo”, e-mail único `responsavel-demo-<sufixo>@example.com` e uma senha temporária que não seja reutilizada). Mostre a sessão iniciada e a lista de usuários. | “O cadastro cria a conta e inicia uma sessão autenticada. As senhas são armazenadas com BCrypt; os endpoints de dados exigem token JWT.” |
| **04:10–05:00** | No formulário Usuários, crie “Ana Silva” com e-mail fictício único e senha temporária. Mostre READ na lista; clique **Editar**, altere o nome para “Ana Souza” e salve. | “Agora demonstro CREATE, READ e UPDATE de usuário pela interface. A API também oferece busca por ID e valida os dados de entrada.” |
| **05:00–05:50** | No formulário Fazendas, selecione Ana Souza como responsável e crie “Fazenda Horizonte”, cidade “Ribeirao Preto”, estado “SP”, área `120.50`. Mostre a fazenda na lista; clique **Editar**, mude o nome para “Fazenda Horizonte II” e a área para `135.00`; salve. | “A fazenda é vinculada a um usuário existente por chave estrangeira. Também demonstro CREATE, READ e UPDATE e a validação dos campos da fazenda.” |
| **05:50–06:35** | Abra Azure SQL Query Editor/cliente SQL e consulte as duas tabelas. Se usar WSL, execute a consulta abaixo; ela pede a senha sem passá-la como argumento visível. | “Os registros aparecem nas tabelas do Azure SQL, demonstrando persistência real fora do processo da aplicação e o relacionamento entre usuário e fazenda.” |
| **06:35–07:20** | Abra Application Insights. Mostre **Transaction search** ou **Logs** com requests e dependências. Se estiver vazio, gere uma atualização na interface e aguarde alguns minutos, depois atualize a consulta. | “O Java Agent envia telemetria para o Application Insights. Aqui estão as requisições e dependências observadas durante o uso da aplicação.” |
| **07:20–08:05** | Volte à interface. Exclua primeiro a Fazenda Horizonte II e depois o usuário Ana Souza. Mostre as mensagens de sucesso e a atualização das listas. | “Demonstro DELETE nas duas entidades. A fazenda é excluída antes do usuário; a chave estrangeira também protege a integridade da relação.” |
| **08:05–08:35** | Mostre rapidamente README, arquitetura e o documento de entrega sem conteúdo privado. | “A entrega inclui instruções de execução, arquitetura, DDL, scripts, exemplos JSON, testes e o roteiro para reproduzir o deploy.” |
| **08:35–09:00** | Encerre com a página inicial da aplicação e/ou o Resource Group ainda ativo. | “Esta foi a demonstração do DimDim com Java 21, Azure App Service, Azure SQL PaaS e Application Insights. Após salvar as evidências, os recursos serão removidos para evitar custos contínuos.” |

## Comandos para as partes ao vivo

### Provisionamento e deploy

Execute na raiz do projeto, no WSL:

```bash
cd /mnt/c/Users/LGA/Documents/checkpoint5-devops/cp4-devops
export PATH="$PATH:/opt/mssql-tools18/bin"
bash scripts/azure-deploy.sh
```

O script roda os testes, inicializa o Azure SQL, publica o artefato usando `az webapp deploy` e repete o health check até a aplicação responder.

### Consulta de persistência no Azure SQL

Carregue as variáveis sem imprimi-las. `SQLCMDPASSWORD` evita colocar a senha administrativa na linha de comando e no histórico:

```bash
set -a
source .env
set +a
export PATH="$PATH:/opt/mssql-tools18/bin"
SQLCMDPASSWORD="$SQL_ADMIN_PASSWORD" sqlcmd \
  -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" \
  -d "$SQL_DATABASE_NAME" \
  -U "$SQL_ADMIN_USERNAME" \
  -N \
  -Q "SELECT ID_USUARIO, NM_USUARIO, DS_EMAIL FROM dbo.TB_USUARIO; SELECT ID_FAZENDA, ID_USUARIO, NM_FAZENDA, DS_CIDADE, DS_ESTADO, NR_AREA_HECTARES FROM dbo.TB_FAZENDA;"
```

Faça essa consulta **depois de criar/editar** os registros e antes de excluí-los. Mostre somente os dados fictícios inseridos para a gravação.

### Exemplo de consulta no Application Insights Logs

No recurso `561413-dimdim-insights`, abra **Logs** e consulte as requests recentes:

```kusto
requests
| where timestamp > ago(30m)
| project timestamp, name, resultCode, success, duration
| order by timestamp desc
```

Para mostrar dependências, incluindo chamadas ao SQL:

```kusto
dependencies
| where timestamp > ago(30m)
| project timestamp, name, target, resultCode, success, duration
| order by timestamp desc
```

A telemetria pode levar alguns minutos para chegar. Gere chamadas na aplicação enquanto espera.

## Checklist imediatamente antes da gravação

- [ ] O deploy terminou com `Deploy e smoke test concluídos`.
- [ ] `/actuator/health` retorna `UP`.
- [ ] A interface abre e aceita registro/login.
- [ ] Os dados de demonstração são fictícios e não incluem informações pessoais reais.
- [ ] A consulta SQL confirma usuários e fazendas relacionados.
- [ ] Requests/dependências do Application Insights já estão visíveis, ou há tempo para aguardar a ingestão.
- [ ] O `.env`, senhas, JWT e connection strings não aparecem na captura.
- [ ] O vídeo está gravando com áudio e resolução legíveis.
- [ ] O teardown ficará para depois de salvar e revisar o vídeo.

## Depois de gravar

1. Revise o vídeo para confirmar que não aparecem `.env`, credenciais, tokens, connection strings ou informações pessoais.
2. Salve e publique o vídeo; copie o link.
3. Preencha nome do grupo, link do repositório e link do vídeo em [`entrega.md`](entrega.md).
4. Confirme que o código publicado não inclui `.env`.
5. Remova os recursos para evitar cobranças:

   ```bash
   cd /mnt/c/Users/LGA/Documents/checkpoint5-devops/cp4-devops
   bash scripts/azure-teardown.sh
   ```

   Digite exatamente o nome do Resource Group solicitado pelo script. A exclusão remove os recursos e os dados Azure; faça-a somente depois de salvar as evidências.
