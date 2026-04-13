# Investigation Briefs

Subagent prompts organized by phase. The main thread reads the relevant brief, replaces
`REPO_PATH` with the actual path, and passes it as the subagent prompt.

Each subagent returns **raw findings with file:line citations**. No synthesis, no
opinions, no polished prose — the main thread handles that.

---

## Phase 1: Orient

### topology

Investigate the physical layout of the repository at `REPO_PATH`.

1. List the top-level directory structure. Skip: .git, node_modules, vendor, __pycache__,
   dist, build, .next, target, venv, .venv, .tox, .mypy_cache, .pytest_cache
2. For each major directory, count source files and estimate LOC. Use Bash:
   ```bash
   find REPO_PATH -type f \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.cs' -o -name '*.swift' -o -name '*.kt' -o -name '*.scala' -o -name '*.ex' -o -name '*.exs' -o -name '*.clj' -o -name '*.zig' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/__pycache__/*' -not -path '*/target/*' -not -path '*/.next/*' -not -path '*/venv/*' -not -path '*/.venv/*' | head -2000 | xargs wc -l 2>/dev/null | tail -1
   ```
   Also break down by extension to get language distribution.
3. Read README.md (first 100 lines) if it exists.
4. Check for monorepo indicators: `workspaces` in package.json, lerna.json, nx.json,
   pnpm-workspace.yaml, `[workspace]` in Cargo.toml, go.work.

**Return:**
- Annotated directory listing (each dir → role/purpose, ~1 line)
- LOC breakdown by language
- Total file count and total LOC
- Shape description: monolith, microservices, monorepo, library, CLI tool, etc.
- File:line citations for any claims

---

### stack

Investigate the technology stack at `REPO_PATH`.

1. Read dependency manifests (first 100 lines of each if large):
   package.json, requirements.txt, pyproject.toml, Pipfile, go.mod, Cargo.toml,
   Gemfile, pom.xml, build.gradle, build.gradle.kts, mix.exs, build.zig
2. Read config: Dockerfile, docker-compose.yml, .tool-versions, .nvmrc,
   .python-version, .ruby-version, rust-toolchain.toml
3. Look for IaC: terraform/, pulumi/, cdk.json, serverless.yml, helm/, k8s/
4. Grep for database/cache/queue clients:
   - DB: `postgres`, `mysql`, `mongodb`, `sqlite`, `redis`, `dynamodb`, `prisma`,
     `typeorm`, `sqlalchemy`, `diesel`, `gorm`, `drizzle`, `knex`
   - Queue: `rabbitmq`, `kafka`, `sqs`, `bull`, `celery`, `sidekiq`, `nats`, `temporal`
   - Cache: `redis`, `memcached`, `valkey`
5. Note version pins, unusual/noteworthy choices, alpha/beta deps

**Return:**
- Categorized list: language + version, framework, DB, cache, queue, cloud, IaC,
  CI/CD, containerization
- Each entry: name, version, source file:line
- Flag anything unusual with a brief note on why it's notable

---

### vocabulary

Investigate domain-specific terminology at `REPO_PATH`.

1. Read README.md, CONTRIBUTING.md, docs/ directory (limit: first 5 files found)
2. Read type/model definitions in: models/, entities/, types/, schema/, domain/,
   src/types, src/models, app/models (limit: first 5 files)
3. Sample 3-5 test files for describe()/it()/test() block names
4. Read API route files or handler directories (sample the main routes file)
5. Identify 15-20 terms that appear frequently, are domain-specific (not generic
   programming terms), and would confuse a newcomer

**Return:**
- Glossary: term → 1-sentence definition inferred from usage context
- Each term: file:line where it's most clearly used or defined
- If fewer than 15 domain terms exist, report what you find — don't pad

---

## Phase 2: Trace

### entry-points

Find every place execution can start at `REPO_PATH`.

Search for:
1. **Main functions**: `if __name__`, `func main`, `fn main`, `public static void main`,
   `bin` field in package.json
2. **HTTP routes**: `app.get`, `app.post`, `router.`, `@app.route`, `@router.`,
   `@GetMapping`, `@PostMapping`, `@RequestMapping`, `HandleFunc`, `mux.Handle`
3. **CLI parsers**: `argparse`, `click`, `cobra`, `clap`, `yargs`, `commander`
4. **Workers/consumers**: celery tasks (`@task`), sidekiq, bull, channel consumers,
   `@Consumer`, `@Process`
5. **Cron/schedulers**: crontab files, `@Scheduled`, `@Cron`, periodic task configs
6. **Event handlers**: `addEventListener`, webhook handlers, SNS/SQS listeners
7. **Serverless**: `exports.handler`, `def handler`, `lambda_handler`

**Return** a table:
| Type | Name | File:Line | Brief |
Limit to 30 entries. If more exist, note the total.

---

### golden-path

Trace one representative user action end-to-end at `REPO_PATH`.

1. Find the primary entry point — the most central HTTP route (e.g., POST to create a
   core resource, or GET for the main page). If no HTTP server, use the main CLI
   command or primary exported function.
2. Trace step by step, reading actual code at each hop (don't guess from names):
   - **Router/dispatcher**: where does the request arrive? File:line.
   - **Middleware**: auth, logging, parsing? File:line for each.
   - **Handler/controller**: what function handles it? File:line.
   - **Service/business logic**: what does the handler call? File:line.
   - **Data layer**: database/API calls? File:line.
   - **Response**: how is the response built and returned? File:line.
3. Note surprising hops (caching layers, event emissions, side effects).

**Return:**
- Numbered sequence of hops: participant name, action description, file:line
- Format should be ready for a Mermaid sequenceDiagram
- If tracing dead-ends (dynamic dispatch, plugin system), note where and why

---

### deploy

Investigate the build and deployment pipeline at `REPO_PATH`.

1. CI config: .github/workflows/*.yml (all, first 100 lines each), .gitlab-ci.yml,
   Jenkinsfile, .circleci/config.yml, bitbucket-pipelines.yml, .travis.yml
2. Build config: Makefile (first 100 lines), Dockerfile, docker-compose.yml,
   package.json scripts, Procfile, webpack/vite/esbuild configs
3. Deploy config: k8s manifests, Helm charts, Terraform/Pulumi/CDK, serverless.yml,
   platform configs (vercel.json, netlify.toml, fly.toml, railway.json, render.yaml)
4. Environment definitions (staging, production, dev)

**Return:**
- Ordered pipeline stages: lint → test → build → push → deploy (or whatever exists)
- Each stage: tool, file:line where defined
- Deploy target(s) and environments
- Enough detail for a Mermaid `graph LR` flow diagram

---

## Phase 3: Map

### architecture

Map the high-level component structure at `REPO_PATH`.

1. Identify component boundaries: separate dirs with their own manifests or Dockerfiles,
   major top-level dirs with distinct concerns, or major modules in a monolith
2. Map communication: HTTP/gRPC between services, queue producers/consumers, shared
   databases, import relationships between major modules (sample 5-10 key files)
3. External dependencies: which components use which databases, caches, APIs
4. The "spine": core data flow from user input to persistent storage

**Return:**
- Component list: name, responsibility, location (dir or file pattern)
- Edge list: source → target, method (HTTP, queue, import, shared DB)
- External services and which components touch them
- Keep to 5-12 components. If more, group related ones.

---

### data-model

Identify core data entities and relationships at `REPO_PATH`.

Look for (in priority order):
1. ORM models: models/, entities/, src/models, app/models
2. DB migrations: migrations/, alembic/, db/migrate/, prisma/migrations
3. Schema definitions: schema.prisma, schema.graphql, openapi.yaml/json
4. Type definitions: types.ts, interfaces/, .proto files
5. Raw DDL: *.sql files with CREATE TABLE

For each entity: name, key attributes (IDs, foreign keys, core fields),
relationships (has-many, belongs-to, many-to-many), source file:line.

**Return:**
- 10-15 core entities with key attributes and relationships
- Enough for a Mermaid erDiagram
- If no formal schema exists, note what you found instead

---

### conventions

Analyze coding conventions at `REPO_PATH`.

Read 8-10 representative files across different parts of the codebase. For each
observation, cite a file:line example.

Investigate:
1. **Naming**: camelCase/snake_case/PascalCase for files, functions, vars, types.
   Prefix/suffix conventions (I- for interfaces, use- for hooks, etc.)
2. **File organization**: flat vs nested, one class per file, index re-exports,
   co-located tests or separate test dir
3. **Error handling**: try/catch, Result types, error middleware, custom error classes
4. **Logging**: structured (JSON) or printf-style, library, log levels
5. **Testing**: framework, location, naming pattern, fixture/mock approach
6. **DI/config**: env vars, config files, DI container, constructor injection
7. **Module patterns**: default vs named exports, dependency direction conventions

Also check linter/formatter config: .eslintrc, .prettierrc, biome.json, .rubocop.yml,
pyproject.toml [tool.ruff], .editorconfig

**Return:**
- Categorized observations with file:line examples
- Only report what you actually see — don't describe framework defaults
- Flag anything surprising or non-standard

---

## Phase 4: Assess

### trust-boundaries

Map the security perimeter at `REPO_PATH`.

Grep for (note file:line for each match):
1. **Authentication**: `authenticate`, `requireAuth`, `@auth`, `passport`, `jwt.verify`,
   `jwt.sign`, `session`, `OAuth`, `OIDC`, `SAML`, `@UseGuards`, `isAuthenticated`
2. **Authorization**: `authorize`, `hasRole`, `hasPermission`, `@Roles`, `canAccess`,
   `RBAC`, `ABAC`, `policy`
3. **Input validation**: `validate`, `sanitize`, `zod`, `joi`, `yup`, `pydantic`,
   `class-validator`, `express-validator`
4. **CORS/CSP**: `cors`, `Content-Security-Policy`, `helmet`, `ALLOWED_ORIGINS`
5. **Rate limiting**: `rateLimit`, `throttle`, `@Throttle`
6. **Secrets**: env vars with KEY/SECRET/TOKEN/PASSWORD in .env.example, config, compose
7. **Data egress**: outbound HTTP clients, webhook dispatchers, email senders

**Return:**
- Boundaries found: type, file:line, what it protects
- Where auth is checked relative to handlers (middleware? per-route? mixed?)
- Routes that appear to lack auth
- Secrets management approach

---

### dragons

Find risk hotspots at `REPO_PATH`.

1. **Code markers**: grep for TODO, HACK, FIXME, XXX, WORKAROUND, TEMPORARY,
   `tech debt`, DEPRECATED, `legacy`. Note file:line and full comment text.
2. **Churn analysis** (if .git exists):
   ```bash
   git -C REPO_PATH log --format=format: --name-only --since='6 months ago' 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -20
   ```
3. **Complexity signals**: files over 500 lines, deeply nested dirs (>4 levels),
   large functions if quickly detectable
4. **Test gaps**: for each major source dir, check if corresponding test files exist
5. **Dead code signals**: commented-out blocks, files not imported by anything

**Return:**
- Hotspot list: type (marker/churn/complexity/untested/dead), file:line, evidence
- Sort by judgment of severity (HACK in auth > TODO in test helper)

---

### observability

Map runtime visibility at `REPO_PATH`.

Grep for:
1. **Logging**: `winston`, `pino`, `bunyan`, `morgan`, `log4j`, `logback`, `slog`,
   `zerolog`, `zap`, `logging` (Python), `tracing` (Rust), `console.log`
2. **Metrics**: `prometheus`, `prom-client`, `statsd`, `datadog`, `micrometer`,
   `Counter`, `Histogram`, `Gauge`, `metrics.`
3. **Tracing**: `opentelemetry`, `jaeger`, `zipkin`, `dd-trace`, `Span`, `tracer`
4. **Error reporting**: `sentry`, `bugsnag`, `rollbar`, `honeybadger`, `errorHandler`
5. **Health checks**: `/health`, `/healthz`, `/ready`, `/ping`, `livenessProbe`,
   `readinessProbe`
6. **Alerting**: alerting rules, PagerDuty/OpsGenie config

**Return:**
- Inventory: tool/library, purpose, file:line examples
- Coverage: which parts of the codebase are instrumented vs. silent
- Logging style: structured vs unstructured, log levels in use
- Gaps: "no metrics", "logging only in API layer", etc.
