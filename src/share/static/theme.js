
const theme = function () {
    /**
     * @type {string}
     */
    const dark = 'dark';

    /**
     * @type {boolean}
     */
    const prefersDarkTheme = window.matchMedia('(prefers-color-scheme: dark)').matches;

    /**
     * @param {boolean?} isDarkMode
     */
    const setTheme = (isDarkMode) => {
        if (isDarkMode == null) {
            isDarkMode = prefersDarkTheme;
        }

        localStorage.setItem('theme', isDarkMode ? dark : 'light');
    };

    /**
     * @param {boolean?} darkMode
     */
    const updateTheme = (darkMode) => {

        if(darkMode === null) {
            setTheme();
        } else if(darkMode != null) {
            setTheme(darkMode);
        } else if(!('theme' in localStorage)) {
            setTheme();
        }

        // On page load or when changing themes, best to add inline in `head` to avoid FOUC
        if (localStorage.theme === dark) {
            document.documentElement.classList.add(dark)
        } else {
            document.documentElement.classList.remove(dark)
        }
    };

    const toggleTheme = () => {
        updateTheme(localStorage.theme !== dark);
    }

    document.onload = updateTheme();

    return {
        toggle: toggleTheme,
    };
}();
