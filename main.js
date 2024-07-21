const { app, BrowserWindow } = require('electron')
const path = require('path')

app.setUserTasks([
	{
		program: process.execPath,
		arguments: '--new-window',
		iconPath: process.execPath,
		iconIndex: 0,
		title: 'New Window',
		description: 'Create a new window',
	},
])
function createWindow() {
	const mainWindow = new BrowserWindow({
		autoHideMenuBar: true,
		width: 860,
		height: 600,
		icon: path.join(__dirname, 'numlex.ico'),
		webPreferences: {
			preload: path.join(__dirname, 'src', 'preload.js'),
			nodeIntegration: true,
			contextIsolation: false,
		},
	})

	mainWindow.loadFile(path.join(__dirname, 'src', 'index.html'))
}

app.on('ready', createWindow)

app.on('window-all-closed', () => {
	if (process.platform !== 'darwin') {
		app.quit()
	}
})

app.on('activate', () => {
	if (BrowserWindow.getAllWindows().length === 0) {
		createWindow()
	}
})
