# Repository Guidelines

## Project Structure & Module Organization
Services for the monitoring demo live under `services/`. The Java Spring Boot services reside in `services/java/service-a`, `service-b`, and `service-c`, each following the standard `src/main/java` and `src/test/java` layout. `services/mock-services` contains the OpenTelemetry-enabled Flask gateway used for mock traffic. Kubernetes manifests live in `kubernetes/base` for shared configuration and `kubernetes/overlays/dev` for Kustomize-driven overrides. Supporting documentation is under `docs/`, Grafana dashboard JSON is in `grafana-dashboards/`, and helper automation is collected in `scripts/`.

## Build, Test, and Development Commands
- `./scripts/deploy-demo.sh`: Builds the mock-service image, loads it into the `kind-monitoring-demo` cluster, and applies `kubernetes/base/services/mock-services.yaml`.
- `./scripts/build-and-deploy.sh`: Iterates through Java and (future) Rust services, builds Docker images, loads them into kind, then applies the dev overlay.
- `kubectl apply -k kubernetes/overlays/dev`: Reconcile manifests after editing overlays or base resources.
- `./scripts/test-services.sh`: Runs smoke tests against the gateway, metrics endpoint, and downstream chains.
- `./scripts/generate-traffic.sh`: Generates steady and burst load so dashboards, alerts, and traces have fresh data.

## Coding Style & Naming Conventions
Use four-space indentation across Java, Python, and YAML. Java packages should remain under `com.example.*`, with classes in PascalCase and methods/fields in camelCase. Place shared service configuration in `src/main/resources/application.yml`. Python code should keep snake_case naming and include type hints where practical. Kubernetes manifests use two-space indentation and should maintain the existing `app.kubernetes.io/*` labelling pattern. Tag Docker images with `:latest` only for local demos; prefer semantic tags (e.g., `service-a:1.2.0`) before distributing more widely.

## Testing Guidelines
Run `mvn clean verify` inside each Java service directory and mirror package structure under `src/test/java` for new tests. Python mock services can be validated with `pytest` once tests are added under `services/mock-services/tests/`. After any deployment change, execute `./scripts/test-services.sh` and capture supporting logs with `kubectl logs -n services <pod>` when diagnosing issues. Cover both success and failure flows that drive Prometheus metrics and Jaeger traces.

## Commit & Pull Request Guidelines
Repository snapshots may omit Git metadata; follow a Conventional Commit style (`feat:`, `fix:`, `chore:`) with imperative subjects no longer than 72 characters. Reference related issue IDs or task links in the body and call out dashboards or manifests touched. Pull requests should describe functional changes, list validation steps (commands run, dashboards inspected), attach screenshots for UI/dashboards, and note any configuration follow-ups. Request reviews from the owners of affected areas (`services/java`, `kubernetes`, `docs`) before merging.

## Security & Configuration Tips
Do not commit kubeconfigs, credentials, or local `.env` files; consume sensitive values via Kubernetes Secrets referenced from `kubernetes/base`. Document OpenTelemetry endpoint or NodePort adjustments in `docs/` and prefer Kustomize patches so `base` remains reusable. Ensure `kubectl config use-context kind-monitoring-demo` is set before applying manifests to avoid updating the wrong cluster.
