{
  system.defaults.NSGlobalDomain = {
    ApplePressAndHoldEnabled = false;

    InitialKeyRepeat = 20;
    KeyRepeat = 1;

    AppleKeyboardUIMode = 3;

    # Disable all automatic substitution
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
  };

  system.keyboard = {
    enableKeyMapping = true;

    remapCapsLockToEscape = true;
    swapLeftCommandAndLeftAlt = false;
    swapLeftCtrlAndFn = false;
  };
}
