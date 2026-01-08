#!/bin/bash

set -e

echo "Desplegando sistema simplificado de logs..."

# Validar que gcloud esté configurado
if ! command -v gcloud &> /dev/null; then
    echo "ERROR: gcloud CLI no encontrado"
    exit 1
fi

# Autenticar Docker con Artifact Registry
echo "Configurando Docker para Artifact Registry..."
REGION=$(grep '^region' terraform.tfvars | cut -d'"' -f2)
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Terraform
echo "Inicializando Terraform..."
terraform init -upgrade

echo "Validando configuración..."
terraform validate

echo "Generando plan..."
terraform plan -out=tfplan

echo "Aplicando cambios..."
terraform apply tfplan

rm -f tfplan

echo ""
echo "Despliegue completado"
echo ""
echo "URLs y recursos:"
terraform output

echo ""
echo "Para probar el sistema:"
echo "$(terraform output -raw test_command)"