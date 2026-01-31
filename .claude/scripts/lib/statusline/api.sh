# api.sh -- Credential retrieval and API functions
# Path: .claude/scripts/lib/statusline/api.sh
# Sourced by statusline.sh — do not execute directly.

get_oauth_token() {
    local creds=""

    case "${PLATFORM}" in
        macos)
            creds=$(security find-generic-password -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null) || return 1
            ;;
        linux)
            if command -v secret-tool &>/dev/null; then
                creds=$(secret-tool lookup service "${KEYCHAIN_SERVICE}" 2>/dev/null) || return 1
            else
                return 1
            fi
            ;;
        windows)
            if command -v powershell.exe &>/dev/null; then
                local ps_script
                ps_script=$(mktemp "${TMPDIR:-/tmp}/claude-cred-XXXXXX.ps1")
                cat >"${ps_script}" <<'PWSH_SCRIPT'
$ErrorActionPreference = 'Stop'
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct NativeCredential {
    public uint Flags;
    public uint Type;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
    [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
    public long LastWritten;
    public uint CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint Persist;
    public uint AttributeCount;
    public IntPtr Attributes;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
    [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
}

public class CredentialReader {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    public static extern void CredFree(IntPtr credential);

    public static string Read(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1, 0, out ptr)) return null;
        var nc = (NativeCredential)Marshal.PtrToStructure(ptr, typeof(NativeCredential));
        var secret = Marshal.PtrToStringUni(nc.CredentialBlob, (int)(nc.CredentialBlobSize / 2));
        CredFree(ptr);
        return secret;
    }
}
'@
    Write-Output ([CredentialReader]::Read('Claude Code-credentials'))
} catch {
    exit 1
}
PWSH_SCRIPT
                local ps_path
                ps_path=$(cygpath -w "${ps_script}" 2>/dev/null || echo "${ps_script}")
                creds=$(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${ps_path}" 2>/dev/null)
                local ps_exit=$?
                rm -f "${ps_script}"
                [[ ${ps_exit} -ne 0 ]] && return 1
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    [[ -z "${creds}" ]] && return 1
    echo "${creds}" | jq -r '.claudeAiOauth.accessToken // empty'
}

fetch_api_usage() {
    local token="$1"

    curl -s --max-time "${CURL_TIMEOUT}" "${API_URL}" \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        -H "anthropic-beta: ${API_BETA_HEADER}" 2>/dev/null || return 1
}

get_api_session_data() {
    local token usage_json utilization resets_at

    token=$(get_oauth_token) || return 1
    [[ -z "${token}" ]] && return 1

    usage_json=$(fetch_api_usage "${token}") || return 1
    [[ -z "${usage_json}" ]] && return 1

    utilization=$(echo "${usage_json}" | jq -r '.five_hour.utilization // empty')
    resets_at=$(echo "${usage_json}" | jq -r '.five_hour.resets_at // empty')

    [[ -z "${utilization}" ]] && return 1

    local weekly_util weekly_reset
    weekly_util=$(echo "${usage_json}" | jq -r '.seven_day.utilization // empty')
    weekly_reset=$(echo "${usage_json}" | jq -r '.seven_day.resets_at // empty')

    printf "%s\t%s\t%s\t%s" "${utilization}" "${resets_at}" "${weekly_util}" "${weekly_reset}"
}
