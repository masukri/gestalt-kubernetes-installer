# echo "Please review your settings (`pwd`/config.yaml):"
echo "The following environment-specific settings will be used:"
echo
cat ./config.yaml | grep -v '^#' | sed 's/ *#.*$//g' | sed 's/^/    /g'

do_prompt_to_continue "Are the settings correct?  If not, please modify them at `pwd`/config.yaml re-start the installation."

