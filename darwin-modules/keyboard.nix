{
  system.defaults.NSGlobaleDomain = {
    ApplePressAndHoldEnabled = false;

    InitialKeyRepeat = 20;
    KeyRepeat = 1;

    AppleKeyboardsUIMode = 3;

    remap = {
      capsLockToControl = true;
      capsLockToEscape = true;
    };

    # Disable all automatic substitution
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
  };

  system.keyboard = {
    enableKeyMapping = true;

    remapCapsLockToControl = true;
    swapLeftCommandAndLeftAlt = false;
    swapLeftCtrlAndFn = false;
  };
}
