{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "rotimi";
  home.homeDirectory = "/home/rotimi";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello
    # my work flow packages
      pkgs.pdm
      pkgs.ruff
      # pkgs.astral-ty  # Use pkgs.ty if that is how it is named in your channel
      pkgs.nodePackages.bash-language-server
      pkgs.shellcheck
      pkgs.yaml-language-server
      pkgs.yamllint
      pkgs.marksman
      pkgs.typos-lsp
      pkgs.codebook # Ensure this is available in your nixpkgs/overlay
      pkgs.zellij
      pkgs.zmate
      pkgs.helix
      pkgs.tlrc
      pkgs.man
      pkgs.stow
      pkgs.aider-chat-full      # The autonomous CLI agent
      pkgs.uv              # Fast python runner (to manage local vector DBs)
    #coding language
      (pkgs.python3.withPackages (ps: with ps; [
    # List your packages here
      numpy
      pandas
      requests
      black
      ipython
      openpyxl
      virtualenv
      ]))
      pkgs.go
      pkgs.ansible
      #infrasctruture management
      pkgs.docker
      pkgs.tenv
      
    # Code quality
      pkgs.ruff
      pkgs.ty
      pkgs.mypy
      pkgs.shellcheck
      pkgs.go-tools

    # Package management
      pkgs.pdm

    #clipboard manager
      pkgs.xclip      
      
    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/rotimi-dev/etc/profile.d/hm-session-vars.sh
  #
  #
# 1. Enable NVIDIA drivers
  nixpkgs.config.allowUnfree = true; 
  # Enable Ollama as a user service
  # services.ollama = {
  #   enable = true;
  #   package = pkgs.ollama-cuda;
  #   acceleration = "cuda"; # Or "rocm" if you're on AMD
  # };
  # services.ollama = {
  #     enable = true;
        
  #     # 2. Configure GPU & Context for your 16GB VRAM
  #     environmentVariables = {
  #       OLLAMA_FLASH_ATTENTION = "1";
  #       OLLAMA_KV_CACHE_TYPE = "q4_0";      # Compresses context to fit more in VRAM
  #       OLLAMA_NUM_PARALLEL = "2";         # Lets the agent do two things at once
  #       # Set your high-priority path if needed
  #       PATH = "$HOME/.local/bin:$PATH";
  #     };
  #   };

  # Don't forget to force the local host in session variables so you never need an API key
  home.sessionVariables = {
    
    OLLAMA_KEEP_ALIVE = "60m"; # Keeps the model in VRAM for 1 hour
    OLLAMA_API_BASE = "http://127.0.0.1:11434";
    # Default to the 'coder' model if you just type 'aider' without arguments
    AIDER_MODEL = "ollama_chat/deepseek-coder-v2:lite";
    LD_LIBRARY_PATH = "/usr/lib/nvidia";
    OLLAMA_FLASH_ATTENTION = "1";
    OLLAMA_KV_CACHE_TYPE = "q4_0";      # Compresses context to fit more in VRAM
    OLLAMA_NUM_PARALLEL = "2";         # Lets the agent do two things at once
    # Set your high-priority path if needed
    PATH = "$HOME/.local/bin:$PATH";

    };

 programs.bash = {
  enable = true;
  # This line is the "safety net" that prevents the command not found error
  bashrcExtra = ''
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    export PATH="/home/rotimi/.opencode/bin:$PATH"
    export PATH="/usr/bin/ollama:$PATH"
  ''; 

 shellAliases = {
  # 1. THE DAILY DRIVER (DeepSeek V2 Lite)
  # Best balance of smarts and context memory. Fits 100% in your VRAM.
  # Uses 'diff' format for speed, but switches to 'whole' if the edit is massive.
  scripter = "aider --model ollama_chat/deepseek-coder-v2:lite --edit-format diff --no-stream --cache-prompts --map-tokens 1024 ";
  coder = "aider --timeout 1200 --model ollama_chat/deepseek-verbose --model-metadata-file ~/.aider.model.metadata.json --edit-format whole --no-stream --cache-prompts --map-tokens 1024";
  # If you work on a HUGE existing codebase, use this one (Lowers map size to save memory)
  legacy-coder = "aider --model ollama_chat/deepseek-coder-v2:lite --edit-format whole --no-stream --map-tokens 512";
  

  # 2. THE ARCHITECT (Qwen 2.5 32B)
  # Maximum intelligence for hard problems. 
  # WARNING: This will spill slightly into System RAM (~19GB total), so it will be slower.
  # We use '--no-stream' strictly here to prevent stuttering while it thinks.
  architect = "aider --timeout 1200 --model ollama_chat/qwen2.5-coder:32b --edit-format diff --no-stream --map-tokens 0";

  # 3. THE SPEED DEMON (Qwen 2.5 14B)
  # Instant replies. Use this for quick scripts, css fixes, or small refactors.
  # It leaves massive room for context, so we enable a huge repo map.

  fastscripter = "aider --timeout 1200 --model ollama_chat/qwen2.5-coder:14b --edit-format diff --no-stream --map-tokens 2048";
  fastcoder = "aider --timeout 1200 --model ollama_chat/qwen2.5-coder:14b --edit-format whole --no-stream --map-tokens 2048";

  };
  };

programs.zellij = {
  enable = true;
  enableBashIntegration = true;
};

programs.git = {
enable = true;
settings.user.name= "Rotimi";
settings.user.email = "olarotimi@protonmail.com";
# alias = {

# };
};

  programs.helix = {
  enable = true;
  languages = {
  language-server = {
    # Python
    ty = { command = "ty"; args = ["server"]; };
    ruff = { command = "ruff"; args = ["server"]; };
    
    # Spellcheckers (codebook: serve, typos: --stdio)
    codebook = { command = "codebook-lsp"; args = ["serve"]; };
    typos = { command = "typos-lsp"; args = ["--stdio"]; };
    
    # Bash, Markdown, and YAML
    bash-lsp = { command = "bash-language-server"; args = ["start"]; };
    marksman = { command = "marksman"; args = ["server"]; };
    yaml-lsp = { command = "yaml-language-server"; args = ["--stdio"]; };
  };

  language = [
    {
      name = "python";
      file-types = ["py" "pyi"]; 
      language-servers = [ "ty" "ruff" "typos" "codebook" ];
      auto-format = true;
    }
    {
      name = "bash";
      file-types = ["sh" "bash" ".bashrc" ".bash_profile"]; 
      language-servers = [ "bash-lsp" "typos" "codebook" ];
    }
    {
      name = "markdown";
      file-types = ["md" "markdown"];
      language-servers = [ "marksman" "typos" "codebook" ];
    }
    {
      name = "yaml";
      file-types = ["yml" "yaml"];
      language-servers = [ "yaml-lsp" "typos" "codebook" ];
    }
  ];
};
};

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
