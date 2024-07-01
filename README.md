
<p align="center">
  <img src="https://github.com/Qulierm/Numlex/assets/132899713/5d48f135-9a20-4b43-93b2-d304bf6c8da3" alt="Sublime's custom image" width="150px" height="150px"/>
</p>

<h1 align="center">Numlex</h1>

A simple and elegant notepad-based calculator to create and manage sheets with real-time syntax highlighting and evaluation for mathematical expressions.
## Features

- **Sheet Management**: Create, switch between, and delete sheets effortlessly.
- **Units and currency convertation**: Covert using special syntax.
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
- **Input Expressions**: Type mathematical expressions in the input area. 
- **View Results**: Results of the evaluated expressions are shown in real-time below the input area.

## Screenshots

<img width="642" alt="QpqkqLXsdh" src="https://github.com/Qulierm/Numlex/assets/132899713/ab330c9e-aee7-46dd-a478-0eeecdd7cd18">


*Main interface with sheet management and real-time evaluation.*

<img width="648" alt="electron_8MvKloREkH" src="https://github.com/Qulierm/Numlex/assets/132899713/8d556065-a2d2-4407-bedc-58f89d6cf087">


*Settings window.*

## Contributing

Contributions are welcome! Please follow these steps to contribute:

1. **Fork the repository**.
2. **Create a new branch** (`git checkout -b feature-branch`).
3. **Commit your changes** (`git commit -m 'Add some feature'`).
4. **Push to the branch** (`git push origin feature-branch`).
5. **Open a pull request**.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
