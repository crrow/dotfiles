{ ... }:

{
  programs.starship = {
    enable = true;
    settings = {
      add_newline     = true;
      command_timeout = 1000;
      format = ''
        $directory$git_branch$git_status$rust$golang$nodejs$python$cmd_duration$line_break$character'';

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol   = "[❯](bold red)";
      };

      directory = {
        style             = "bold cyan";
        truncation_length = 4;
        truncate_to_repo  = true;
      };

      git_branch = {
        symbol = " ";
        style  = "bold purple";
      };

      cmd_duration = {
        min_time = 2000;
        format   = " [$duration](dim yellow)";
      };
    };
  };
}
