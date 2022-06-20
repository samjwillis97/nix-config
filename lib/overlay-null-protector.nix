# Thanks to https://github.com/divnix/digga/issues/464
overlay:

final: prev:

if prev == null || (prev.isFakePkgs or false)
then { }
else overlay final prev
