# Zips the current folder with a timestamped filename
zipdate() {
    foldername="${1%/}"
    timestamp=$(date +'%Y-%m-%d-%H-%S-%M')
    zip -r "${timestamp}.zip" "$foldername"
}