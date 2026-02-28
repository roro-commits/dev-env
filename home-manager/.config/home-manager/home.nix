{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "rawonria";
  home.homeDirectory = "/home/rawonria";

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
      # pkgs.aider-chat-full      # The autonomous CLI agent
      pkgs.uv              # Fast python runner (to manage local vector DBs)
    #coding language
      (pkgs.python312.withPackages (ps: with ps; [
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
  # 1. Define and export your environment variables
  home.sessionVariables = let
    certPath = "/etc/ssl/certs/ca-certificates.crt";
    certDir = "/etc/ssl/certs/";
  in {
    SSL_CERT_FILE = certPath;
    SSL_CERT_DIR = certDir;
    CURL_CA_BUNDLE = certPath;
    cacert = certPath;
    REQUESTS_CA_BUNDLE = certPath;
    NODE_EXTRA_CA_CERTS = certPath;
  };

  # 2. Add Klocwork directories to your PATH
  home.sessionPath = [
    "/opt/klocwork/desktoptools/kw-cmd/kw-cmd/bin"
    "/opt/klocwork/buildtools/kwbuildtools/bin"
  ];

  # ... the rest of your configuration ...


  programs.bash = {
  enable = true;
  # This line is the "safety net" that prevents the command not found error
  bashrcExtra = ''
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
  ''; 

 shellAliases = {
    kwcmd = "ls -r /opt/klocwork/desktoptools/kw-cmd/kw-cmd/bin";
    kwtools = "ls  -r  /opt/klocwork/buildtools/kwbuildtools/bin";
    xcopy = "xclip -selection clipboard";
    xpaste = "xclip -o"; 
    ruff-strict = "ruff check --extend-select ANN";
  };
  };

programs.zellij = {
  enable = true;
  enableBashIntegration = true;
};

programs.git = {
enable = true;
settings.user.name= "rawonria";
settings.user.email = "rawonria@jaguarlandrover.com";
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
