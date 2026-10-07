# Arquitetura DimDim

```mermaid
flowchart LR
    browser[Usuário / Browser]
    subgraph appService["Azure App Service Linux · Java 21"]
        spring[DimDim · Spring Boot]
        agent[Application Insights Java Agent]
        spring -. instrumenta .-> agent
    end
    insights[Azure Application Insights]
    subgraph sql["Azure SQL Server · PaaS"]
        database[(Azure SQL Database)]
    end

    browser -->|HTTPS · HTML/CSS/JavaScript| spring
    browser -->|HTTPS · API REST| spring
    spring -->|JDBC TLS · usuário de banco restrito| database
    agent -->|requests, dependências, logs e exceções| insights
```

O frontend estático e a API são servidos pela mesma aplicação Spring Boot. O Azure SQL é um serviço PaaS independente, e não há containers ou imagens Docker no caminho de implantação.
