# DimDim — aplicações e banco em nuvem

Aplicação Web e API REST Java para gerenciar usuários e suas fazendas, preparada para o checkpoint de Cloud Computing da FIAP. A solução usa Java 21, Spring Boot, Azure App Service Linux, Azure SQL Database PaaS e Azure Application Insights. O deploy é executado pela Azure CLI com `az webapp deploy`; não utiliza Docker, ACI, ACR ou GitHub Actions.

## Objetivo

Demonstrar uma aplicação Web publicada na Azure, com persistência relacional real, operações CRUD completas nas duas entidades e telemetria da aplicação. Um usuário pode possuir várias fazendas; a relação existe no Azure SQL por meio de uma chave estrangeira.

## Tecnologias

- Java 21, Spring Boot e Maven.
- Spring Data JPA com Microsoft SQL Server JDBC Driver.
- Spring Security stateless com JWT e senha armazenada por hash BCrypt.
- Azure App Service Linux (Java SE 21).
- Azure SQL Server lógico e Azure SQL Database (PaaS).
- Azure Application Insights com o Java Agent oficial.
- Azure CLI, `az webapp deploy`, `sqlcmd`, `curl` e `zip`.
- Springdoc OpenAPI / Swagger UI.

## Arquitetura

O browser acessa o frontend estático e a API REST no mesmo App Service. A API se conecta por JDBC/TLS ao Azure SQL Database. O Application Insights Java Agent instrumenta a aplicação e envia telemetria ao recurso Application Insights.

Veja o desenho macro em [`docs/architecture.md`](docs/architecture.md).

## Estrutura do projeto

```text
src/main/java/br/com/fiap/dimdim/  controllers, services, entities, DTOs e repositories
src/main/resources/static/         interface web
src/test/                           testes de integração HTTP usando H2 somente em testes
scripts/                            DDL, inicialização SQL, deploy, teardown e validação
docs/api/                           exemplos JSON das operações REST
docs/architecture.md                desenho da arquitetura
docs/entrega.md                      dados de apoio para o PDF
```

## Pré-requisitos

- JDK 21 e Azure CLI instalados.
- Maven Wrapper incluído (`mvnw`); não é necessário instalar Maven.
- Bash (WSL ou Git Bash no Windows), `curl`, `zip` e `sqlcmd`.
- Uma subscription Azure com permissões para criar Resource Group, Azure SQL, App Service e Application Insights.
- Acesso de rede do host do deploy ao Azure SQL (o `CLIENT_IP` é detectado e liberado no firewall; veja [Variáveis de ambiente](#variáveis-de-ambiente)).

## Configuração local

Crie seu arquivo local de variáveis (ele não deve ser versionado):

```bash
cp .env.example .env
```

Preencha no `.env` os nomes dos recursos, o login administrativo do servidor SQL, o usuário contido da aplicação e o `JWT_SECRET`. Use senhas próprias e fortes; não as inclua em commits, screenshots públicos ou vídeos.

Para iniciar localmente conectado ao Azure SQL já criado:

```bash
set -a
source .env
set +a
export DATABASE_URL="jdbc:sqlserver://${SQL_SERVER_NAME}.database.windows.net:1433;database=${SQL_DATABASE_NAME};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30"
bash ./mvnw spring-boot:run
```

A aplicação usa `DATABASE_URL`, `DATABASE_USERNAME` e `DATABASE_PASSWORD`. Em Azure, elas são definidas como App Settings. Não há banco local de substituição em execução normal; H2 é utilizado exclusivamente pelo perfil de testes.

## Variáveis de ambiente

Consulte [`.env.example`](.env.example). As variáveis sensíveis obrigatórias para provisionamento são:

- `SQL_ADMIN_USERNAME` e `SQL_ADMIN_PASSWORD`: login administrativo do Azure SQL usado apenas pelo script de inicialização.
- `DATABASE_USERNAME` e `DATABASE_PASSWORD`: usuário contido com acesso CRUD ao database, utilizado pela aplicação.
- `JWT_SECRET`: chave aleatória com pelo menos 32 bytes para assinatura dos tokens; `JWT_EXPIRATION` é a validade em milissegundos.

Gere `JWT_SECRET` localmente com `openssl rand -base64 32` e guarde o valor apenas no `.env` (e nos App Settings do Azure). Não use uma chave de exemplo em produção.

As principais variáveis de nomenclatura têm valores padrão, mas podem ser alteradas no `.env`: `RM`, `RESOURCE_GROUP`, `SQL_SERVER_NAME`, `SQL_DATABASE_NAME`, `APP_SERVICE_PLAN`, `WEB_APP_NAME` e `APP_INSIGHTS_NAME`. O nome de Web App precisa ser globalmente único.

Variáveis de região e rede:

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `LOCATION` | não | `eastus2` | Região do Resource Group, App Service Plan, Web App e Application Insights. |
| `SQL_LOCATION` | não | valor de `LOCATION` | Região do Azure SQL Server. Use outra região apenas se a primeira não tiver capacidade para SQL. |
| `CLIENT_IP` | não | detectado automaticamente | IPv4 público do host que executa o deploy; pode ser informado manualmente se a detecção falhar. |

Em produção a aplicação roda com `SPRING_PROFILES_ACTIVE=azure`, que carrega [`application-azure.properties`](src/main/resources/application-azure.properties): o pool Hikari não derruba a subida se o banco estiver indisponível (`initialization-fail-timeout=-1`), o Hibernate não consulta metadados JDBC na inicialização e os probes de health do Actuator ficam habilitados. Essas propriedades existem somente nesse perfil; os testes (perfil `test`, H2) não são afetados. O App Service usa a porta 8080 (explícita) e Always On fica ativado. `AZURE_SUBSCRIPTION_ID` é opcional se a subscription correta já estiver ativa.

`CLIENT_IP` é o IPv4 público exato do host que executa o deploy e `sqlcmd`; é detectado automaticamente e só precisa ser definido se a detecção falhar. O fluxo automatizado o utiliza para inicializar Azure SQL. Isso cria somente uma regra individual chamada `AllowTemporaryClientIP`. O valor especial `0.0.0.0` a `0.0.0.0` da regra `AllowAzureServices` permite conexões originadas em serviços hospedados no Azure e não é uma liberação universal. Remova a regra temporária após o trabalho:

```bash
az sql server firewall-rule delete \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name AllowTemporaryClientIP
```

## Azure SQL

O DDL idempotente está em [`scripts/azure-sql.sql`](scripts/azure-sql.sql): cria `TB_USUARIO`, `TB_FAZENDA`, PKs, FK com `ON DELETE CASCADE`, restrição positiva para a área e índice da FK.

O script `azure-sql-init.sh` aplica o DDL e cria/atualiza o usuário contido da aplicação, dando apenas `db_datareader` e `db_datawriter`. Requer `sqlcmd` e conectividade permitida pelo firewall. As contas de demonstração são criadas pelo endpoint de registro para que a senha seja armazenada com hash BCrypt.

## Criação da infraestrutura e deploy

> **⚠️ AVISO — não crie App Service Plan em loop nem rode teardown entre tentativas.** Criar e apagar planos repetidamente na mesma região pode fazer a Azure bloquear a capacidade daquela região por tempo prolongado. Se algo falhar depois que a infraestrutura existe, **corrija e use `--app-only`** (build + deploy + validação, sem recriar nada). Use `--preflight-only` antes de qualquer criação e só rode o teardown ao final do trabalho.

1. Copie e preencha `.env`.
2. Faça login e confirme a subscription:

   ```bash
   az login
   if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
     az account set --subscription "$AZURE_SUBSCRIPTION_ID"
   fi
   az account show --output table
   ```

3. Gere e preencha `JWT_SECRET` (`openssl rand -base64 32`). `LOCATION` (padrão `eastus2`), `SQL_LOCATION` e `CLIENT_IP` são opcionais.
4. **Rode primeiro o preflight** (somente leitura, não cria nada):

   ```bash
   bash scripts/azure-deploy.sh --preflight-only
   ```

5. Execute o fluxo completo:

   ```bash
   bash scripts/azure-deploy.sh
   ```

Modos do script:

| Comando | O que faz |
|---|---|
| `bash scripts/azure-deploy.sh` | Fluxo completo: infraestrutura, banco, build, deploy e validação. |
| `bash scripts/azure-deploy.sh --preflight-only` | Somente leitura. Rode antes de tudo. |
| `bash scripts/azure-deploy.sh --infra-only` | Cria/reutiliza apenas a infraestrutura. |
| `bash scripts/azure-deploy.sh --app-only` | Ciclo rápido de correções: build + deploy + validação, sem recriar a infraestrutura. |

Cada execução grava um log em `logs/deploy-<modo>-<timestamp>.log`; confira que não contém segredos antes de compartilhá-lo.

O fluxo completo cria/reutiliza Resource Group, Azure SQL Server, database, regra restrita para serviços Azure e regra do IP local, App Service Plan Linux B1, Web App Java 21 (porta 8080 explícita, Always On ativado) e Application Insights. Inicializa o DDL e o usuário de banco, executa `./mvnw clean test package`, baixa o Application Insights Java Agent oficial (versão 3.7.9), prepara o pacote, configura App Settings (incluindo o `JWT_SECRET`) e publica via `az webapp deploy`. Por fim, valida a aplicação em duas fases (veja [Validação](#validação)).

O Application Insights connection string é consultado no recurso Azure durante o deploy e armazenado apenas nos App Settings do Web App (`APPLICATIONINSIGHTS_CONNECTION_STRING`). O agente Java é iniciado com `-javaagent` e coleta telemetria de requests, dependências, logs, métricas e exceções. Nenhum connection string é salvo no repositório.

Se o `WEB_APP_NAME` padrão já estiver ocupado, escolha outro valor globalmente único no `.env` e repita o deploy. `RESOURCE_GROUP` define o escopo removido pelo teardown.

## Validação

O deploy valida a aplicação em duas fases:

1. `GET /` — confirma que o container subiu e responde na porta 8080 (não depende do banco).
2. `GET /actuator/health` — confirma a aplicação e a conexão com o Azure SQL (o health do Spring Boot inclui o datasource).

Se alguma fase falhar por tempo, o script coleta automaticamente os logs do App Service.

O script [validate.sh](scripts/validate.sh) também pode ser executado isoladamente. As APIs CRUD exigem JWT e não são chamadas sem autenticação pelo script:

```bash
BASE_URL="https://SEU-WEB-APP.azurewebsites.net" bash scripts/validate.sh
```

Interpretação rápida: `/` OK e health OK = tudo certo; `/` OK e health `DOWN` = problema de banco/credenciais; `/` sem resposta = problema no container ou na porta.

URLs da aplicação:

- Interface Web: `https://SEU-WEB-APP.azurewebsites.net/`
- Swagger UI: `https://SEU-WEB-APP.azurewebsites.net/swagger`
- OpenAPI JSON: `https://SEU-WEB-APP.azurewebsites.net/api-docs`
- Health: `https://SEU-WEB-APP.azurewebsites.net/actuator/health`

## Testes

```bash
bash ./mvnw --batch-mode clean test
bash ./mvnw --batch-mode clean package
```

Os testes exercitam autenticação JWT, endpoints protegidos, validação, busca de recurso inexistente, operações CRUD e o relacionamento Usuário–Fazenda. H2 é carregado pelo perfil `test`, sem mudar a configuração de produção `spring.jpa.hibernate.ddl-auto=none`.

## Endpoints e exemplos

As operações CRUD completas estão disponíveis para ambas as entidades:

| Entidade | Listar | Buscar por ID | Criar | Atualizar | Excluir |
|---|---|---|---|---|---|
| Usuário | `GET /api/usuarios` | `GET /api/usuarios/{id}` | `POST /api/usuarios` | `PUT /api/usuarios/{id}` | `DELETE /api/usuarios/{id}` |
| Fazenda | `GET /api/fazendas` | `GET /api/fazendas/{id}` | `POST /api/fazendas` | `PUT /api/fazendas/{id}` | `DELETE /api/fazendas/{id}` |

Para criar a primeira conta, use `POST /api/auth/register`; para obter um token depois, use `POST /api/auth/login`. Os endpoints CRUD requerem `Authorization: Bearer <token>`. Swagger permite inserir o token pelo botão **Authorize**. Senhas são armazenadas como hash BCrypt, nunca retornadas pela API. Fazendas podem ser filtradas por responsável com `GET /api/fazendas?usuarioId=1`. A criação e atualização de fazenda requerem `usuarioId` válido.

Os exemplos de request/response estão em [`docs/api/`](docs/api/):

- [`usuario-get.json`](docs/api/usuario-get.json), [`usuario-post.json`](docs/api/usuario-post.json), [`usuario-put.json`](docs/api/usuario-put.json), [`usuario-delete.json`](docs/api/usuario-delete.json).
- [`fazenda-get.json`](docs/api/fazenda-get.json), [`fazenda-post.json`](docs/api/fazenda-post.json), [`fazenda-put.json`](docs/api/fazenda-put.json), [`fazenda-delete.json`](docs/api/fazenda-delete.json).

### Roteiro de CRUD para a gravação

Defina a URL do Web App, registre o primeiro usuário (a resposta contém o JWT e o `id`) e copie o token e ID retornados:

```bash
export BASE_URL="https://SEU-WEB-APP.azurewebsites.net"
curl -i -X POST "$BASE_URL/api/auth/register" -H "Content-Type: application/json" \
  -d '{"nome":"Responsável","email":"responsavel@example.com","senha":"senha-forte-exemplo"}'
export TOKEN="<copie-o-token-retornado>"
export OWNER_ID="<copie-o-id-retornado>"
```

Use o token para o CRUD de usuários e fazendas:

```bash
curl -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/usuarios"
curl -i -X POST "$BASE_URL/api/usuarios" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nome":"Ana Silva","email":"ana@example.com","senha":"senha-forte-exemplo"}'
export USER_ID="<copie-o-id-do-usuario-criado>"
curl -i -X PUT "$BASE_URL/api/usuarios/$USER_ID" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nome":"Ana Souza","email":"ana.souza@example.com"}'
```

Crie uma fazenda usando o ID do usuário criado:

```bash
curl -i -X POST "$BASE_URL/api/fazendas" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"usuarioId\":$USER_ID,\"nome\":\"Fazenda Horizonte\",\"cidade\":\"Ribeirao Preto\",\"estado\":\"SP\",\"areaHectares\":120.50}"
curl -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/fazendas"
export FARM_ID="<copie-o-id-da-fazenda-criada>"
curl -i -X PUT "$BASE_URL/api/fazendas/$FARM_ID" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"usuarioId\":$USER_ID,\"nome\":\"Fazenda Horizonte II\",\"cidade\":\"Ribeirao Preto\",\"estado\":\"SP\",\"areaHectares\":135.00}"
```

Depois de registrar as criações e atualizações, mostre a persistência no Azure SQL e exclua primeiro a fazenda e depois o usuário:

```bash
sqlcmd -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" -d "$SQL_DATABASE_NAME" \
  -U "$SQL_ADMIN_USERNAME" -P "$SQL_ADMIN_PASSWORD" -N \
  -Q "SELECT * FROM dbo.TB_USUARIO; SELECT * FROM dbo.TB_FAZENDA;"
curl -i -X DELETE "$BASE_URL/api/fazendas/$FARM_ID" -H "Authorization: Bearer $TOKEN"
curl -i -X DELETE "$BASE_URL/api/usuarios/$USER_ID" -H "Authorization: Bearer $TOKEN"
```

IDs são identity e aumentam; use sempre os IDs retornados pelas respostas reais, não presuma que serão `1`.

## Application Insights

Após o deploy, abra o recurso Application Insights configurado em `APP_INSIGHTS_NAME` no portal Azure. Use **Investigate > Transaction search** ou **Logs** para demonstrar requests/dependências; acesse a página e execute chamadas CRUD antes de consultar. A ingestão pode levar alguns minutos. O script também mostra o App Service URL e registra o connection string apenas na configuração do recurso.

## Evidências para o vídeo

Grave em 720p ou superior, com explicação falada:

1. Provisionamento (ou recursos já criados), App Service, Azure SQL e Application Insights.
2. Preflight (`--preflight-only`), build/testes e deploy executados por `scripts/azure-deploy.sh` com `az webapp deploy`, mostrando o log gerado em `logs/`.
3. Interface Web ou Swagger, incluindo CREATE, READ, UPDATE e DELETE de Usuário e Fazenda.
4. Consultas no Azure SQL após operações para demonstrar persistência e FK.
5. Requests/telemetria visíveis no Application Insights.

O roteiro detalhado do vídeo, com fala sugerida, comandos e minutagem, está em [`docs/roteiro-video.md`](docs/roteiro-video.md). O artefato para registrar os links está em [`docs/entrega.md`](docs/entrega.md). Os links reais do GitHub e do vídeo devem ser preenchidos antes de montar o PDF.

## Troubleshooting

- **Região sem capacidade para SQL ou B1**: erros como `RegionDoesNotAllowProvisioning` ou "not available in this region". Rode `--preflight-only`, defina `SQL_LOCATION` com outra região (o SQL pode ficar em região diferente do App Service) ou altere `LOCATION`. Não crie e apague planos repetidamente (veja o aviso acima).
- **Firewall demorando a propagar**: a regra do `CLIENT_IP` pode levar alguns minutos para valer. Se o `sqlcmd` falhar logo após criar a regra, aguarde e repita; não amplie a faixa de IPs.
- **Container não responde na porta**: `/` não responde dentro do tempo. Confirme que a porta 8080 está configurada no App Service e que `PORT`/`WEBSITES_PORT` não apontam para outra porta; leia os logs coletados pelo script (e o `logs/deploy-*.log`) procurando, por exemplo, `JWT_SECRET` inválido/curto, que impede a aplicação de subir. Corrija e use `--app-only`.
- **Health `DOWN` com `/` OK**: a aplicação subiu, mas o banco não responde. Verifique `DATABASE_URL`, `DATABASE_USERNAME` e `DATABASE_PASSWORD` nos App Settings, a regra `AllowAzureServices` e se o usuário contido foi criado por `azure-sql-init.sh`. Corrija e use `--app-only`.
- **Erro de firewall/timeout SQL**: confirme `CLIENT_IP`, a regra temporária e se `AllowAzureServices` existe. Não abra uma faixa ampla.
- **Login SQL falha**: confira `SQL_ADMIN_USERNAME`, `SQL_ADMIN_PASSWORD`, `DATABASE_USERNAME` e `DATABASE_PASSWORD`; confirme que `DATABASE_USERNAME` difere do administrador e rode novamente `bash scripts/azure-sql-init.sh`.
- **JWT inválido/401**: confirme o token Bearer e `JWT_SECRET`; o valor da chave não pode mudar entre a emissão e validação do token.
- **Nome de Web App ocupado**: altere `WEB_APP_NAME` para um nome globalmente único.
- **Erro real aparecendo como 401**: a rota `/error` e `/actuator/health/**` são públicas, então falhas de endpoints públicos aparecem com o status real em vez de 401.
- **Aplicação retorna 500 no deploy**: valide que o DDL foi executado, confira App Settings e logs de diagnóstico do App Service.
- **Telemetria não aparece imediatamente**: gere requests na aplicação e aguarde alguns minutos; confirme `APPLICATIONINSIGHTS_CONNECTION_STRING` nos App Settings.
- **`sqlcmd` ausente**: instale o SQL Server Command Line Utilities para seu sistema e confirme `sqlcmd --version`.

## Teardown

O teardown pede o nome completo do Resource Group; nenhuma exclusão ocorre sem confirmação exata:

```bash
bash scripts/azure-teardown.sh
```

Não rode o teardown entre tentativas de deploy (veja o aviso em [Criação da infraestrutura e deploy](#criação-da-infraestrutura-e-deploy)); use-o somente depois de salvar as evidências. Confirme que o Resource Group configurado é exclusivo do projeto. O comando exclui o grupo e todos os seus recursos/dados de forma assíncrona.

## Integrantes

| Nome | RM |
|---|---:|
| Lucas Grillo Alcântara | 561413 |
| Pietro Ferreira Gomes Abrahamian | 561469 |
| Pedro Peres Benitez | 561792 |
| Lucca Ramos Mussumecci | 562027 |

## Checklist do Checkpoint

### Aplicação
- [ ] Java
- [ ] Web App
- [ ] Não é Sprint 3
- [ ] Deploy Azure

### Banco
- [ ] Azure SQL
- [ ] PaaS
- [ ] 2 tabelas relacionadas
- [ ] CRUD tabela 1
- [ ] CRUD tabela 2

### Azure
- [ ] Azure CLI
- [ ] App Service
- [ ] Application Insights
- [ ] az webapp deploy

### GitHub
- [ ] Descrição
- [ ] Arquitetura
- [ ] DDL
- [ ] Scripts CLI
- [ ] Código
- [ ] How To
- [ ] JSON
- [ ] Vídeo

### Segurança
- [ ] Sem credenciais no código
- [ ] .env ignorado
- [ ] Sem tokens versionados

### Vídeo
- [ ] Criação dos recursos
- [ ] Deploy
- [ ] Testes
- [ ] CRUD tabela 1
- [ ] CRUD tabela 2
- [ ] Persistência no Azure SQL
- [ ] Application Insights
