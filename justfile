#import 'justfile-dir/service.just'
#import? 'justfile-dir/guickget-check.just'

#mod? quickget-check
# Justfile - Enhanced with Multi-Level Interactive Commands
# This Justfile integrates ripgrep (rg), fzf, zoxide, and aspell (optional)
# to provide a deep, interactive command-line experience.
# Ensure the following tools are installed:
#   - ripgrep (rg)
#   - fzf
#   - bat
#   - zoxide
#   - aspell (optional, for spell-check hints)
#
# Usage examples:
#   just service [pattern]
#   just search <pattern>
#   just files
#   just jump [dir]
#   (plus other Nix and Git commands as defined below)
# ===== Settings ===== #
# Define aliases for frequent commands

alias b := rebuild
alias d := ezaD
alias a := ezaA
alias l := list-generations
alias gs := status
alias j := just
alias r := upfrefresh
alias g := gact
alias u := update-github-at
alias v := view-github-at
alias rb := rebuild-fast

# Set Justfile options

set positional-arguments := true
set shell := ["bash", "-c"]

just:
    @just --list --color=always

# ===== System & Utilities ===== #

# List directories (using eza as ls alternative)
[group("File Utilities")]
ezaD:
    @eza -D

# List all files (incl. hidden) with details (using eza)
[group("File Utilities")]
ezaA:
    @eza -ola

# --- Advanced Systemctl Management ---
#
# Interactive multi-level systemctl management command.
# This recipe does the following:
# 1. Lists all systemd service unit files (filtered by an optional pattern).
# 2. Uses fzf to let you select a service.
# 3. Optionally checks for typos using aspell.
# 4. Confirms the selected service.
# 5. Uses fzf to select a desired action (status, start, stop, restart, enable, disable, etc.).
# 6. Asks for final confirmation before executing sudo systemctl.
#
# # Usage:
# #   just service [optional-filter-pattern]
# [doc("Multi-level interactive systemctl management (includes spell-check hints)")]
# [group("System")]
# service pattern="" action="":
# 	#!/run/current-system/sw/bin/bash
# 	# 1. Get list of service unit files, optionally filtering with the pattern
# 	if [ -n "{{pattern}}" ]; then
# 		echo "Filtering services for pattern \"{{pattern}}\"..."
# 		services=$(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}' | rg -i "{{pattern}}")
# 	else
# 		services=$(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}')
# 	fi
# 	if [ -z "$services" ]; then
# 		echo "No services found matching pattern." >&2
# 		exit 0
# 	fi
# 	# 2. Use fzf to select a service
# 	service=$(echo "$services" | fzf --prompt "Select service: ")
# 	if [ -z "$service" ]; then
# 		echo "No service selected." >&2
# 		exit 0
# 	fi
# 	# 3. Optional: Spell-check the service name (if aspell is installed)
# 	if command -v aspell >/dev/null 2>&1; then
# 		suggestions=$(echo "$service" | aspell list)
# 		if [ -n "$suggestions" ]; then
# 			echo "Warning: The service name \"$service\" might be misspelled. Suggestions:" >&2
# 			echo "$suggestions" >&2
# 		fi
# 	fi
# 	# 4. Confirm the selected service
# 	read -p "Confirm selected service [$service] (Y/n)? " confirm
# 	if [ "$confirm" != "" ] && [ "$confirm" != "Y" ] && [ "$confirm" != "y" ]; then
# 		echo "Aborting."; exit 0
# 	fi
# 	# 5. Select an action via fzf if not provided
# 	if [ -z "{{action}}" ]; then
# 		action=$(printf "status\nstart\nstop\nrestart\nenable\ndisable\nenable-now\ndisable-now" | fzf --prompt "Select action: ")
# 		if [ -z "$action" ]; then
# 			echo "No action selected." >&2; exit 0
# 		fi
# 	else
# 		action="{{action}}"
# 	fi
# 	# 6. Final confirmation before execution
# 	read -p "Execute 'sudo systemctl $action $service'? (Y/n) " final
# 	if [ "$final" != "" ] && [ "$final" != "Y" ] && [ "$final" != "y" ]; then
# 		echo "Command aborted."; exit 0
# 	fi
# 	echo "Executing: sudo systemctl $action $service"
# 	sudo systemctl "$action" "$service"

# # Open man pages in Firefox browser
[group("System")]
man subject:
    @man --html=firefox --all {{ subject }}

# Fuzzy find and open a file from current directory (via fzf)

# Preview file content with bat; opens the selected file in $EDITOR
[group("Search & Navigate")]
files:
    #!/run/current-system/sw/bin/bash
    if ! command -v rg &>/dev/null || ! command -v fzf &>/dev/null || ! command -v bat &>/dev/null; then
        echo "Error: Required tools (ripgrep, fzf, bat) are not installed." >&2
        exit 1
    fi
    file=$(rg --files --hidden --glob "!.git" --glob "!node_modules" 2>/dev/null | \
        fzf --prompt "Select file: " \
            --preview "bat --style=numbers --color=always {}" \
            --preview-window=right:60%:wrap)
    if [ -z "$file" ]; then
        echo "No file selected." >&2
        exit 0
    fi
    if [ ! -f "$file" ]; then
        echo "Error: Selected file does not exist." >&2
        exit 1
    fi
    exec ${EDITOR:-nano} "$file"

# Jump to a directory (using zoxide & fzf)

[doc("Jump to a directory via zoxide; spawn shell in that directory")]
[group("Search & Navigate")]
jump dir="":
    #!/run/current-system/sw/bin/bash
    PATTERN="{{ dir }}"
    if [ -z "$PATTERN" ]; then
        DIR=$(zoxide query -i)
    else
        DIR=$(zoxide query -i "$PATTERN")
    fi
    if [ -z "$DIR" ]; then
        echo "No directory found for: $PATTERN" >&2
        exit 0
    fi
    cd "$DIR" && exec ${SHELL:-bash}

# ===== Nix Commands ===== #

[group("NixOS")]
list-generations:
    @nixos-rebuild list-generations

[group("Nix Flake")]
upfrefresh:
    # Update all flake inputs
    just update-github-at
    nix flake update --refresh
    just gact "updates from flake udpate"

[group("Nix Flake")]
upflock:
    nix flake lock
    just gact "updates from flake lock"

# [group("Nix Flake")]
# upflock-dir:
# 	# Update nix-ld-dir flake.lock
# 	cd nix-ld-dir && nix flake lock

[group("Nix Flake")]
upuinput:
    @nix flake metadata --json | nix run nixpkgs#jq '.locks.nodes.root.inputs[]' | \
      sed 's/"//g' | nix run nixpkgs#fzf | xargs nix flake update --repair --refresh

[group("Nix Flake")]
show:
    @sudo nix flake metadata

[group("Nix Flake")]
check:
    @nix flake check --refresh

# [group("NixOS")]
# rebuild-container:
#     # Rebuild container
#     #sudo nixos-rebuild switch --flake . #--target-host hadicloud@192.168.0.10
#--cores 2 --max-jobs 3 --show-trace

[group("NixOS")]
rebuild-thermal-safe:
    # Rebuild the system with conservative settings to prevent overheating
    just update-github-at
    sudo nixos-rebuild --cores 6 --max-jobs 3 --verbose --keep-going switch --flake .#inixos
    just gact "updates from thermal-safe rebuild"
    sudo nix store optimise

[group("NixOS")]
rebuild:
    # Rebuild the system
    just update-github-at
    sudo nixos-rebuild --verbose --log-format bar-with-logs --print-build-logs --json boot --flake .#inixos
    just gact "updates from rebuild"
    sudo nix store optimise

[group("Helpful Scripts")]
update-github-at:
    @bash ./ease-of-use-scripts/update-access-token.sh
    @just v
    #echo "viewing $0 results"

[group("Scripts Secrets")]
view-github-at:
    @cat /etc/nix/nix.custom.conf | rg -i access | rev | cut -c-7
    #echo "Current $0 result"

[group("NixOS Containers")]
rebuild-container:
    # Rebuild the system
    #sudo nixos-rebuild switch --flake . 2>&1 | sudo tee "/var/log/rebuild/rebuild-$(date +%Y%m%d-%H%M%S).log"
    sudo nixos-rebuild test --flake '.#inixos-container'
    just update-github-at
    just gact "updates from rebuild-slow"
    sudo nix store optimise

[group("NixOS Containers")]
rebuild-slow-container message="":
    #!/run/current-system/sw/bin/bash
    # Check if a message is provided
    if [ -z "{{ message }}" ]; then
        echo "From the rebuild-slow group:: No commit message provided. Please provide a message or use 'just rebuild-slow message=\"Your message\"'."
    else
        # Exporting NIX_SHOW_STATS = "1";
        #export NIX_SHOW_STATS="0";
        # Performing gact
        just gact "{{ message }}" && just upfrefresh
        # Performing upfrefresh

        # Performing gact
        just gact "{{ message }}" && just upfrefresh
        # Performing upfrefresh

        # Performing gact
        just gact "{{ message }}"
        # Rebuild the system
        just rebuild-container

    fi

[group("gact upfrefresh gact switch")]
switch message="":
    #!/run/current-system/sw/bin/bash
    if [ -z "{{ message }}" ]; then
      echo "need a message"
      exit 1
    else
      just gact "{{ message }}"
      just r
      just gact "{{ message }}"
      # just r
      # just gact "{{ message }}"
      sudo nixos-rebuild --verbose --log-format bar-with-logs --show-trace --print-build-logs --json --flake .'#inixos' switch
      #sudo nixos-rebuild --json --flake .'#inixos' test
    fi

[group("NixOS Rebuild-Slow")]
rebuild-slow message="":
    #!/run/current-system/sw/bin/bash
    # Check if a message is provided
    if [ -z "{{ message }}" ]; then
        echo "From the rebuild-slow group:: No commit message provided. Please provide a message or use 'just rebuild-slow message=\"Your message\"'."
    else
        # Exporting NIX_SHOW_STATS = "1";
        #export NIX_SHOW_STATS="0";
        # Performing gact
        just gact "{{ message }}"
        # Performing upfrefresh
        just upfrefresh
        # Performing gact
        just gact "{{ message }}"
        # Performing upfrefresh
        just upfrefresh
        # Performing gact
        just gact "{{ message }}"
        # Rebuild the system
        just rebuild

    fi

[group("NixOS Rebuild-Fast")]
rebuild-fast:
    just gact "Rebuilding system with fast switch" && \
    just upfrefresh && \
    just upflock && \
    just gact "Flake inputs updated" && \
    just rebuild
    # Rebuild the system with fast switch

[doc("Refresh flake inputs, commit changes, and rebuild system")]
[group("NixOS")]
gr message="":
    #!/run/current-system/sw/bin/bash
    #just add
    if [ -z "{{ message }}" ]; then
        echo "From gr group:: No commit message provided. Please provide a message or use 'just gr message=\"Your message\"'."
        #just gact "next time provide a message" && just upfrefresh && just gact "no message provided"
    else
        just update-github-at
        just rebuild-slow message="{{ message }}"
    fi

[doc("Refresh flake inputs, commit changes, and rebuild inixos-container")]
[group("NixOS-Container")]
gr-container message="":
    #!/run/current-system/sw/bin/bash
    #just add
    if [ -z "{{ message }}" ]; then
        echo "From gr group:: No commit message provided. Please provide a message or use 'just gr message=\"Your message\"'."
        #just gact "next time provide a message" && just upfrefresh && just gact "no message provided"
    else
        just rebuild-slow-container message="{{ message }}"
    fi

[doc("View latest rebuild log")]
[group("NixOS")]
view-log:
    #!/run/current-system/sw/bin/bash
    # Find the most recent log file
    LATEST_LOG=$(ls -t /var/log/rebuild/rebuild*.log 2>/dev/null | head -n 1)
    if [ -z "$LATEST_LOG" ]; then
        echo "No log files found in logs directory"
        exit 1
    fi
    # Display the log file
    cat "$LATEST_LOG"

[group("Nix Packages")]
locate pkg:
    @nix-search --flake flake:nixpkgs --verbose=0 -e '{{ pkg }}'

[group("Nix Packages")]
locatb pkg:
    @nix-search --flake flake:nixpkgs --verbose=true '{{ pkg }}'

[group("Nix Packages")]
buildpkgs pkg:
    @nix build nixpkgs#"{{ pkg }}"

[group("Nix Packages")]
run pkg:
    @nix shell nixpkgs#"{{ pkg }}"

[group("Nix Packages")]
repl:
    @nix repl -f flake:nixpkgs

[group("Nix GC")]
gc days:
    #!/run/current-system/sw/bin/bash
    if [ -f /.dockerenv ]; then
        echo "Running in container environment. Using nix commands without sudo..."
        nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than {{ days }}d
        nix-collect-garbage --delete-older-than {{ days }}d
    else
        sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than {{ days }}d
        sudo nix-collect-garbage --delete-older-than {{ days }}d
    fi

[group("Nix GC")]
gc-all:
    # Without sudo
    nix-store --gc
    nix store gc
    nix-collect-garbage -d
    nix-collect-garbage
    nix store optimise
    # With sudo
    sudo nix-store --gc
    sudo nix store gc
    sudo nix-collect-garbage -d
    sudo nix-collect-garbage
    sudo nix store optimise

# ===== Git Commands ===== #

[group("git")]
gitdiff:
    @git diff -- ':^flake.lock' ':^pkgs/_sources/*'

[group("git")]
gitdiffcached:
    @git diff --cached -- ':^flake.lock' ':^pkgs/_sources/*'

[doc("Commit changes (if no message is provided, editor opens)")]
[group("git")]
commit message="":
    #!/run/current-system/sw/bin/bash
    if [ -z "{{ message }}" ]; then
        git commit
    else
        git commit -m "{{ message }}"
    fi

[group("git")]
status:
    @git status

[group("git")]
i:
    @git status --ignored

[group("git")]
add:
    git add .

[group("git")]
lint:
    @treefmt .

[doc("Format code, stage changes, commit with optional message, and show status")]
[group("git")]
gact message="":
    #!/run/current-system/sw/bin/bash
    # Run formatting first
    if ! just lint; then
        echo "Formatting failed" >&2
        exit 1
    fi
    # If formatting succeeded, proceed with git operations
    just gac "{{ message }}"

[doc("Stage changes, commit with optional message, and show status")]
[group("git")]
gac message="":
    #!/run/current-system/sw/bin/bash
    # Stage changes
    just add
    # Commit with message or open editor
    if [ -z "{{ message }}" ]; then
        git commit --signed
    else
        git commit -m "{{ message }}"
    fi
    # Show status
    git status

[group("git")]
pull:
    @git pull --rebase

# Knowledge system commands
[group("Knowledge")]
learn TYPE DESC SOLUTION:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh learn "{{ TYPE }}" "{{ DESC }}" "{{ SOLUTION }}"

[group("Knowledge")]
analyze:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh analyze

[group("Knowledge")]
suggest TYPE CONTEXT:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh suggest "{{ TYPE }}" "{{ CONTEXT }}"

[group("Knowledge")]
kreport:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh report

[group("Knowledge")]
kinit:
    @find nixos/tools -name "*.sh" -exec chmod +x {} +
    @./nixos/tools/knowledge-system.sh init
    @./nixos/tools/knowledge-system.sh hook

# Alias for quick access

k := "kinit"

[group("Shell Aliases")]
code-ins:
    @~/Documents/vscode-insider/usr/share/code-insiders/bin/code-insiders

[group("Shell Aliases")]
z:
    @zoxide query -i

[group("Shell Aliases")]
zsh:
    @zsh

[group("Shell Aliases")]
ll:
    @eza --long --header --inode --git --all

[group("Shell Aliases")]
lt:
    @eza --long --tree --level=4 --all

[group("Shell Aliases")]
u-reset:
    @sudo systemctl reset-failed && sudo systemctl daemon-reload && systemctl --user reset-failed && systemctl --user daemon-reload

[group("Shell Aliases")]
u-off:
    @sudo systemctl poweroff

[group("Shell Aliases")]
u-boot:
    sudo systemctl reboot

[group("Shell Aliases")]
u-0:
    sudo nix store diff-closures /run/*-system

[group("Shell Aliases")]
u-9:
    sudo nix profile diff-closures --profile /nix/var/nix/profiles/system

# [group("Shell Aliases")]
# u-8:
#     nvd --color=always --version-highlight=bold history -p /nix/var/nix/profiles/system --sort=semver -s --list-oldest

# [group("Shell Aliases")]
# u-7:
#     nvd --color=always --version-highlight=bold history -p /nix/var/nix/profiles/system --sort=semver --list-oldest

[group("Shell Aliases")]
u-1:
    nix run .#nixosConfigurations.inixos.config.facter.debug.nix-diff

[group("Shell Aliases")]
u-2:
    nix run .#nixosConfigurations.inixos.config.facter.debug.nvd && echo $@
