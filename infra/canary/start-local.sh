#!/usr/bin/env bash
# Usado por infra/docker-compose.yml (serviço server). Aplica rates opcionais em
# config.lua antes do bootstrap da imagem (MySQL, schema, sed de IP/portas, canary).
set -euo pipefail
cd /canary

apply_rates_from_env() {
	[[ -f config.lua ]] || return 0
	if [[ -n "${OT_RATE_EXP:-}" ]]; then
		if [[ "${OT_RATE_EXP}" =~ ^[0-9]+$ ]]; then
			sed -i "/^rateExp = .*$/c\\rateExp = ${OT_RATE_EXP}" config.lua
			echo "[start-local] rateExp = ${OT_RATE_EXP}"
		else
			echo "[start-local] Aviso: OT_RATE_EXP ignorado (usa só inteiro, ex.: 50)." >&2
		fi
	fi
	if [[ -n "${OT_RATE_USE_STAGES:-}" ]]; then
		case "$(printf '%s' "${OT_RATE_USE_STAGES}" | tr '[:upper:]' '[:lower:]')" in
			true|1|yes)
				sed -i "/^rateUseStages = .*$/c\\rateUseStages = true" config.lua
				echo "[start-local] rateUseStages = true (multipliers em data/stages.lua)"
				;;
			false|0|no)
				sed -i "/^rateUseStages = .*$/c\\rateUseStages = false" config.lua
				echo "[start-local] rateUseStages = false (usa só rateExp)"
				;;
			*)
				echo "[start-local] Aviso: OT_RATE_USE_STAGES ignorado (usa true ou false)." >&2
				;;
		esac
	fi
}

apply_rates_from_env
exec bash /canary/start.sh
