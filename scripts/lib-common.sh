#!/usr/bin/env bash
# Funções comuns (apenas definições; sem efeitos colaterais). Usar com `source`.

# Retorna 0 se $1 é um IPv4 válido (4 octetos 0-255).
is_ipv4() {
  local ip="$1" octet
  local -a parts
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a parts <<< "$ip"
  for octet in "${parts[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

# 189.12.34.56 -> 189.12.x.x
mask_ip() {
  local a b
  IFS=. read -r a b _ _ <<< "$1"
  printf '%s.%s.x.x' "$a" "$b"
}

# Filtro de stdin: mascara os dois últimos octetos de qualquer IPv4.
mask_ips() {
  sed -E 's/\b([0-9]{1,3})\.([0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}\b/\1.\2.x.x/g'
}
