.PHONY: help init plan apply deploy test clean destroy

help:
	@echo "Comandos disponibles:"
	@echo "  make init     - Inicializar Terraform"
	@echo "  make plan     - Ver plan de cambios"
	@echo "  make deploy   - Desplegar todo"
	@echo "  make test     - Ejecutar tests"
	@echo "  make clean    - Limpiar archivos temporales"
	@echo "  make destroy  - Destruir infraestructura"

init:
	terraform init -upgrade

plan:
	terraform plan

deploy:
	@chmod +x scripts/deploy.sh
	@./scripts/deploy.sh

test:
	@chmod +x scripts/test.sh
	@./scripts/test.sh

clean:
	rm -rf .terraform .terraform.lock.hcl tfplan
	rm -rf .terraform/tmp/

destroy:
	@echo "⚠️  ADVERTENCIA: Vas a destruir la infraestructura"
	@read -p "Escribe 'yes' para confirmar: " confirm && [ "$$confirm" = "yes" ] || exit 1
	terraform destroy -auto-approve