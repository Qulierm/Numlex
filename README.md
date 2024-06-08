# Numlex

<p align="center">
  <img src="https://i.ibb.co/fCsBtDq/numlex.png" alt="Sublime's custom image" width="150px" height="150px"/>
</p>
A simple and elegant Electron-based application to create and manage sheets with real-time syntax highlighting and evaluation for mathematical expressions.

## Features

- **Sheet Management**: Create, switch between, and delete sheets effortlessly.
- **Real-time Syntax Highlighting**: Differentiate between numbers, operators, and text as you type.
- **Math Expression Evaluation**: Evaluate mathematical expressions and display the result instantly.
- **Customizable Interface**: Clean and modern UI with dark mode.

## Building the Application

To package the application into an executable file, follow these steps:

1. **Install the necessary build tools**:
    ```sh
    npm install electron-builder --save-dev
    ```

2. **Build for Windows**:
    ```sh
    npm run dist
    ```

   The packaged application will be found in the `dist` directory.

## Usage

- **Create a New Sheet**: Click on the "New Sheet" button to create a new sheet.
- **Switch Sheets**: Click on a sheet in the sidebar to switch to it.
- **Delete a Sheet**: Hover over a sheet in the sidebar and click the delete icon to remove it.
- **Input Expressions**: Type mathematical expressions in the input area. Numbers will be highlighted in blue, operators in white, and text in green.
- **View Results**: Results of the evaluated expressions are shown in real-time below the input area.

## Screenshots

![2024-06-09_00-16-09](https://github.com/Qulierm/Numlex/assets/132899713/f69f2f4e-5b96-4fb2-a0ff-7f057927cf81)
*Main interface with sheet management and real-time evaluation.*

![screenshot](https://github.com/Qulierm/Numlex/assets/132899713/d34577b4-7c63-4c5c-8698-61ded1e9d785)
*Deleting a sheet by clicking on the delete icon.*

## Contributing

Contributions are welcome! Please follow these steps to contribute:

1. **Fork the repository**.
2. **Create a new branch** (`git checkout -b feature-branch`).
3. **Commit your changes** (`git commit -m 'Add some feature'`).
4. **Push to the branch** (`git push origin feature-branch`).
5. **Open a pull request**.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
