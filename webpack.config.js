const path = require('path')

module.exports = {
	mode: 'development',
	entry: './src/main.ts',
	target: 'electron-main',
	module: {
		rules: [
			{
				test: /\.ts$/,
				include: /src/,
				use: [{ loader: 'ts-loader' }],
			},
		],
	},
	resolve: {
		extensions: ['.ts', '.js'],
	},
	output: {
		filename: 'main.js',
		path: path.resolve(__dirname, 'dist/src'),
	},
}
