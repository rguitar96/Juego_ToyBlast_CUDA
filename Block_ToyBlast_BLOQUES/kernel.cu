
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <curand_kernel.h>

#include <time.h>
#include <stdio.h>
#include <conio.h>
#include <iostream>
#include <sstream>
#include <sys/stat.h>
#include <vector>
#include <Windows.h>
#include <fstream>

using namespace std;

//FUNCIONES CPU
bool existeFichero(const string& fichero);
void setFontSize(int FontSize);
void cargarPartida(const string& fichero, int tam_tesela);
void tableroAleatorio(vector<vector<int>>& tablero, int dificultad);
void nuevaPartida(vector<vector<int>>& tablero, int dificultad, int filas, int columnas, int puntuacion, int tam_tesela);
void imprimirTablero(vector<vector<int>>& tablero);
void guardarPartida(vector<vector<int>> tablero, string nombre, int filas, int columnas, int dificultad, int puntuacion);
bool quedanMovimientosF(vector<vector<int>> tablero);

#define TILE_WIDTH 16

//FUNCIONES GPU
__global__ void ToyBlast(int *tablero, int filas, int columnas, int fila, int columna, int *puntuacion);
__device__ void eliminarPieza(int *tablero, int filas, int columnas, int fila, int columna, int valor_ini, int *cont);
__device__ void bombaRotorH(int* tablero, int filas, int columnas, int fila, int columna);
__device__ void bombaRotorV(int* tablero, int filas, int columnas, int fila, int columna);
__device__ void bombaTNT(int* tablero, int filas, int columnas, int fila, int columna);
__device__ void bombaPuzzle(int* tablero, int filas, int columnas, int fila, int columna);

int main(int argc, char *argv[])
{
	SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15);
	cudaDeviceProp propiedades;
	cudaGetDeviceProperties(&propiedades, 0);
	int hilos_max = propiedades.maxThreadsPerBlock;
	int tam_tesela = TILE_WIDTH;

	//SI HAY MÁS ARGUMENTOS QUE argv[0]
	if (argc > 1) {
		//SI SÓLO HAY UN ARGUMENTO MÁS, SE CARGA EL FICHERO CON ESE NOMBRE
		if (argc == 2) {
			cargarPartida(argv[1], tam_tesela);
		}
		else {
			//SI HAY TRES ARGUMENTOS MÁS, SE CARGA LA PARTIDA CON (dificultad, filas, columnas)
			if (argc == 4) {
				int dificultad = atoi(argv[1]);
				int filas = atoi(argv[2]);
				int columnas = atoi(argv[3]);
				vector<vector<int>> tablero;
				tablero.resize(filas, vector<int>(columnas, 0));

				//SE ALEATORIZA EL TABLERO Y SE INICIA LA PARTIDA
				tableroAleatorio(tablero, dificultad);
				nuevaPartida(tablero, dificultad, filas, columnas, 0, tam_tesela);

			}
			else {
				cout << "El archivo debe ejecutarse de una de las tres maneras:\n-Sin argumentos.\n-Con un unico argumento indicando el nombre del fichero a cargar.\n-Con tres argumentos indicando dificultad, filas y columnas del nuevo tablero.\n";
			}
		}
	}
	else {

		bool valido = false;
		bool nueva = true;
		string fichero;

		while (!valido) {
			cout << "Si desea cargar una partida, introduzca su nombre con la extension (.txt). Presione enter para iniciar una nueva partida.\n";

			getline(cin, fichero);

			if (fichero != "") {
				//COMPROBAMOS SI EL FICHERO EXISTE, SI NO VOLVEMOS A PREGUNTAR
				if (existeFichero(fichero)) {
					valido = true;
					nueva = false;
				}
				else {
					cout << "El fichero no existe.";
				}
			}
			else {
				//NUEVA PARTIDA
				valido = true;
			}
		}

		if (nueva) {
			//INICIO NUEVA PARTIDA

			cout << "Por favor, introduzca el numero de filas.\n";
			int filas;
			
			//GET FILAS
			while (!(cin >> filas)) {
				cin.clear();
				cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
				cerr << "Por favor, introduzca un numero de fila valido.\n";
			}

			cout << "Por favor, introduzca el numero de columnas.\n";
			int columnas;

			//GET COLUMNAS
			while (!(cin >> columnas)) {
				cin.clear();
				cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
				cerr << "Por favor, introduzca un numero de columna valido.\n";
			}

			//GET DIFICULTAD
			int dificultad = -1;
			while (dificultad != 2 && dificultad != 1) {
				cout << "Por favor, introduzca la dificultad (1 para dificultad facil y 2 para dificil).\n";
				while (!(cin >> dificultad)) {
					cin.clear();
					cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
					cerr << "Por favor, introduzca un numero de dificultad valido.\n";
				}
				if (dificultad != 2 && dificultad != 1) {
					cout << "Entrada invalida.\n";
				}
			}
			
			//SI EL TABLERO NO CABE EN PANTALLA, SE HACE LA LETRA MÁS PEQUEÑA
			if (columnas > 48) {
				setFontSize(11);
				if (columnas > 55) setFontSize(8);
				if (columnas > 75) setFontSize(6);
				if (columnas > 90) setFontSize(4);
			}

			vector<vector<int>> tablero;
			tablero.resize(filas, vector<int>(columnas, 0));

			tableroAleatorio(tablero, dificultad);

			nuevaPartida(tablero, dificultad, filas, columnas, 0, tam_tesela);
		}
		else {
			cargarPartida(fichero, tam_tesela);
		}
	}
	return 0;
}

inline bool existeFichero(const string& fichero) {
	struct stat buffer;
	return (stat(fichero.c_str(), &buffer) == 0);
}

void cargarPartida(const string& fichero, int tam_tesela) {
	//YA SE HA COMPROBADO QUE EL ARCHIVO EXISTE, CARGAR ARCHIVO EXISTENTE
	vector<int> datavec;

	ifstream infile;
	infile.open(fichero, ios::in | ios::binary);

	while (infile) {
		int val;
		infile.read(reinterpret_cast<char *>(&val), sizeof(int));
		if (infile.bad()) {
			throw std::runtime_error("Failed to read from infile!");
		}
		if (infile.eof()) break;
		datavec.push_back(val);
	}

	//FORMATO DEL FICHERO: un vector de enteros con vector[0]=puntuacion, vector[1]=filas, vector[2]=columnas, vector[3]=dificultad, y la matriz en una lista unidimensional de enteros
	int puntuacion = datavec[0];
	datavec.erase(datavec.begin());
	int filas = datavec[0];
	datavec.erase(datavec.begin());
	int dificultad = datavec[0];
	datavec.erase(datavec.begin());

	int columnas = (datavec.size()) / filas;

	vector<vector<int>> tablero;
	tablero.resize(filas, vector<int>(columnas, 0));
	imprimirTablero(tablero);
	for (int i = 0; i < filas; i++) {
		for (int j = 0; j < columnas; j++) {
			tablero[i][j] = datavec[0];
			datavec.erase(datavec.begin());
		}
	}
	nuevaPartida(tablero, dificultad, filas, columnas, puntuacion, tam_tesela);

}

void setFontSize(int FontSize)
{
	//PONER LA FUENTE A CIERTO TAMAÑO
	CONSOLE_FONT_INFOEX info = { 0 };
	info.cbSize = sizeof(info);
	info.dwFontSize.Y = FontSize;
	info.FontWeight = FW_NORMAL;
	wcscpy(info.FaceName, L"Lucida Console");
	SetCurrentConsoleFontEx(GetStdHandle(STD_OUTPUT_HANDLE), NULL, &info);
}

void tableroAleatorio(vector<vector<int>>& tablero, int dificultad) {
	srand(time(NULL));
	//MODIFICA TODOS LOS HUECOS LIBRES DEL TABLERO (QUE SEAN 0) CON BLOQUES ALEATORIOS
	if (dificultad == 1) {
		for (int i = 0; i < tablero.size(); ++i) {
			for (int j = 0; j < tablero[0].size(); ++j) {
				if (tablero[i][j] == 0) tablero[i][j] = rand() % 5 + 1;
			}
		}
	}
	else {
		for (int i = 0; i < tablero.size(); ++i) {
			for (int j = 0; j < tablero[0].size(); ++j) {
				if (tablero[i][j] == 0) tablero[i][j] = rand() % 6 + 1;
			}
		}
	}
}

void imprimirTablero(vector<vector<int>>& tablero) {
	//IMPRIMIR CABECERA
	cout << "#_____________TABLERO_DE_JUEGO_____________\n\n       ";
	SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 8 + 15 * 16);
	for (int i = 0; i < tablero[0].size(); ++i) {
		if (i % 2 == 0) {
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 1 + 16 * 8);
		}
		else {
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15 + 16 * 1);
		}
		cout << " ";
		if (i + 1 < 10) cout << " ";
		cout << i + 1;
		if (i + 1 < 100) cout << " ";
	}
	cout << "\n";

	//IMPRIMIR CADA POSICIÓN
	for (int i = 0; i < tablero.size(); ++i) {
		if (i % 2 == 0) {
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 1 + 16 * 8);
		}
		else {
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15 + 16 * 1);
		}
		cout << "  ";
		if (i + 1<10) cout << " ";
		if (i + 1 < 100) cout << " ";
		cout << i + 1;
		cout << "  ";
		for (int j = 0; j < tablero[0].size(); ++j) {
			switch (tablero[i][j]) {
			case 1:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+9*16);
				break;
			case 2:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+12*16);
				break;
			case 3:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+5*16); //NO HAY COLOR NARANJA
				break;
			case 4:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+2*16);
				break;
			case 5:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+6*16);
				break;
			case 6:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+14*16);
				break;
			case 7:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+10*16);
				break;
			case 8:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+10*16);
				break;
			case 9:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+11*16);
				break;
			default:SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15+13*16);
				break;
			}
			cout << " ";
			if (tablero[i][j] < 10) cout << " ";
			cout << tablero[i][j];
			cout << " ";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15);
		}
		cout << "\n";
	}
}

void nuevaPartida(vector<vector<int>>& tablero, int dificultad, int filas, int columnas, int puntuacion, int tam_tesela) {
	system("CLS");

	ShowWindow(GetConsoleWindow(), SW_MAXIMIZE);
	//IMPRIMIR TABLERO
	imprimirTablero(tablero);


	//LEER FILA Y COLUMNA DE LA JUGADA
	int fila = -1;
	bool quedanMovimientos = true;
	while (fila != 0 && quedanMovimientos) {
		printf("Puntuacion actual: %d,\n", puntuacion);
		while (fila < 0 || fila > filas) {
			cout << "Introduce la fila de la pieza a eliminar (0 para salir). Los rotores horizontales son:";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 10);
			cout << " 7";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15);
			cout << ", los verticales son: ";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 10);
			cout << " 8";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15);
			cout << ", las bombas TNT son: ";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 11);
			cout << " 9";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15);
			cout << ", las bombas puzzle son: ";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 13);
			cout << "1X";
			SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), 15);
			cout << ", donde X indica el valor que eliminan.\n";
			while (!(cin >> fila)) {
				cin.clear();
				cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
				cerr << "Por favor, introduzca un numero de fila valido.\n";
			}
			if (fila < 0 || fila > filas) cout << "Fila fuera de rango.\n";
		}

		if (fila != 0) {
			int columna = 0;
			while (columna < 1 || columna > columnas) {
				cout << "Introduce la columna de la pieza a eliminar.\n";
				while (!(cin >> columna)) {
					cin.clear();
					cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
					cerr << "Por favor, introduzca un numero de columna valido.\n";
				}
				if (columna < 1 || columna > columnas) cout << "Columna fuera de rango.\n";
			}
			//FIN LEER FILA Y COLUMNA DE LA JUGADA

			int mayor = max(filas, columnas);

			//CUDA
			int *d_tablero;
			int *d_puntuacion;

			//DADO QUE CUDA NO SOPORTA VECTORES, PASAMOS EL VECTOR A ARRAY UNIDIMENSIONAL
			int* tablero_a = new int[tablero.size()*tablero[0].size()];
			for (int i = 0; i < tablero.size(); ++i) {
				for (int j = 0; j < tablero[0].size(); ++j) {
					tablero_a[i*tablero[0].size() + j] = tablero[i][j];
				}
			}

			//ALOCAMOS MEMORIA PARA EL TABLERO Y COPIAMOS NUESTRO ARRAY DE CPU A GPU
			cudaMalloc(&d_tablero, (tablero.size()*tablero[0].size()*sizeof(int)));
			cudaMemcpy(d_tablero, tablero_a, (tablero.size()*tablero[0].size()*sizeof(int)), cudaMemcpyHostToDevice);

			cudaMalloc(&d_puntuacion, (sizeof(int)));
			cudaMemcpy(d_puntuacion, &puntuacion, sizeof(int), cudaMemcpyHostToDevice);

			int n_bloques = (mayor+tam_tesela-1) / tam_tesela;

			dim3 DimGrid(n_bloques, n_bloques);
			dim3 DimBlock(tam_tesela, tam_tesela, 1);

			ToyBlast << < DimGrid, DimBlock >> > (d_tablero, filas, columnas, fila - 1, columna - 1, d_puntuacion);

			//UNA VEZ TERMINA, VOLVEMOS A COPIAR EL ARRAY DE GPU A CPU
			cudaMemcpy(tablero_a, d_tablero, tablero.size()*tablero[0].size()*sizeof(int), cudaMemcpyDeviceToHost);
			cudaMemcpy(&puntuacion, d_puntuacion, sizeof(int), cudaMemcpyDeviceToHost);


			//PASAMOS EL ARRAY A VECTOR
			for (int i = 0; i < tablero.size(); ++i) {
				for (int j = 0; j < tablero[0].size(); ++j) {
					tablero[i][j] = tablero_a[i*tablero[0].size() + j];
				}
			}

			//RELLENAMOS LOS CEROS CON ALEATORIO
			tableroAleatorio(tablero, dificultad);
			imprimirTablero(tablero);

			//LIBERAMOS MEMORIA DE GPU
			cudaFree(d_tablero);
			cudaFree(d_puntuacion);
			fila = -1;
			quedanMovimientos = quedanMovimientosF(tablero);
		}
		else {
			cout << "¿Deseas guardar la partida? Introduzca 0 para no o 1 para si.\n";
			int guardar;
			while (!(cin >> guardar)) {
				cin.clear();
				cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
				cerr << "Por favor, introduzca un valor valido.\n";
			}
			if (guardar == 1) {
				string nombre;
				cout << "Introduzca el nombre de la partida a guardar.\n";
				cin >> nombre;
				guardarPartida(tablero, nombre, filas, columnas, dificultad, puntuacion);
			}
		}
	}
	if (!quedanMovimientos) {
		printf("No quedan movimientos posibles. Su puntuacion ha sido:\n %d \n GRACIAS POR JUGAR\n", puntuacion);
	}
}

void guardarPartida(vector<vector<int>> tablero, string nombre, int filas, int columnas, int dificultad, int puntuacion) {
	//GUARDAR LA PARTIDA SERIALIZANDO EL VECTOR COMO ARRAY UNIDIMENSIONAL DE ENTEROS
	ofstream outfile;
	outfile.open(nombre, ios::out | ios::trunc | ios::binary);

	outfile.write(reinterpret_cast<const char *>(&puntuacion), sizeof(int));
	outfile.write(reinterpret_cast<const char *>(&filas), sizeof(int));
	outfile.write(reinterpret_cast<const char *>(&dificultad), sizeof(int));
	for (int i = 0; i < tablero.size(); i++) {
		for (int j = 0; j < tablero[0].size(); j++) {
			outfile.write(reinterpret_cast<const char *>(&tablero[i][j]), sizeof(int));
			if (outfile.bad()) {
				throw std::runtime_error("Failed to write to outfile!");
			}
		}
	}
}

bool quedanMovimientosF(vector<vector<int>> tablero) {
	//SI NO HAY DOS PIEZAS JUNTAS EN NINGÚN ESPACIO DEL TABLERO, NO QUEDAN MOVIMIENTOS
	for (int i = 0; i < tablero.size(); i++) {
		for (int j = 0; j < tablero[0].size(); j++) {
			if (tablero[i][j]>6) return true;
			if ((i>0) && (tablero[i][j] == tablero[i - 1][j])) return true;
			if (((i + 1)<tablero.size()) && (tablero[i][j] == tablero[i + 1][j])) return true;
			if ((j>0) && (tablero[i][j] == tablero[i][j - 1])) return true;
			if (((j + 1)<tablero[0].size()) && (tablero[i][j] == tablero[i][j + 1])) return true;
		}
	}
	return false;
}


__global__ void ToyBlast(int *tablero, int filas, int columnas, int fila, int columna, int *puntuacion) {
	int hilo_fila = blockIdx.x*blockDim.x + threadIdx.x;
	int hilo_columna = blockIdx.y*blockDim.y + threadIdx.y;
	if (hilo_fila == fila && hilo_columna == columna) {
		int cont = 0;
		int valor = tablero[fila*columnas + columna];
		eliminarPieza(tablero, filas, columnas, fila, columna, valor, &cont);
		if (cont < 2) {
			tablero[fila*columnas + columna] = valor;
		}
		else {
			if (cont > 4) {
				//crearBomba
				switch (cont) {
				case 5: int aleatorio = clock() % 10;
					if (aleatorio < 5) {
						tablero[fila*columnas + columna] = 7; //SE CREA ALEATORIAMENTE UN ROTOR HORIZONTAL O VERTICAL
					}
					else {
						tablero[fila*columnas + columna] = 8;
					}
					break;
				case 6: tablero[fila*columnas + columna] = 9;
					break;
				default: tablero[fila*columnas + columna] = 10 + valor; //PARA ALMACENAR EL BLOQUE A EXPLOTAR DEL PUZZLE, LA BOMBA SERA DE 11 A 16 EN FUNCIÓN DEL COLOR
					break;
				}
			}
		}

		if (cont>1) *puntuacion = *puntuacion + cont;
	}
	__syncthreads();
	
	
	//SUBIR TODOS LOS CEROS
	if (hilo_columna < columnas&&hilo_fila < filas) {
	for (int i = 1; i < filas; i++) {
		
			if (tablero[(filas - i)*columnas + hilo_columna] == 0) {
				if (tablero[(filas - (i + 1))*columnas + hilo_columna] == 0) {
					int j = i;
					while (tablero[(filas - (j + 1))*columnas + hilo_columna] == 0 && j < filas) {
						j++;
					}
					tablero[(filas - i)*columnas + hilo_columna] = tablero[(filas - (j + 1))*columnas + hilo_columna];
					tablero[(filas - (j + 1))*columnas + hilo_columna] = 0;
				}
				else {
					tablero[(filas - i)*columnas + hilo_columna] = tablero[(filas - (i + 1))*columnas + hilo_columna];
					tablero[(filas - (i + 1))*columnas + hilo_columna] = 0;
				}
			}
			__syncthreads();

		}
	}
}

__device__ void eliminarPieza(int *tablero, int filas, int columnas, int fila, int columna, int valor_ini, int *cont) {
	//DECLARAMOS BOOLEANOS PARA SABER HACIA DONDE TIENE QUE COMPROBAR SI TIENE QUE ELIMINAR LA PIEZA, SI TIENE QUE COMPROBARLA VOLVEMOS A LLAMAR A eliminarPieza
	int valor_act = tablero[fila*columnas + columna];

	if ((valor_act == valor_ini) && (valor_act<7)) {
		tablero[fila*columnas + columna] = 0;
		*cont = *cont + 1;

		bool arriba = true;
		bool abajo = true;
		bool izquierda = true;
		bool derecha = true;

		if (fila < 1) arriba = false;
		if (columna < 1) izquierda = false;
		if (fila + 1 >= filas) abajo = false;
		if (columna + 1 >= columnas) derecha = false;

		if (arriba) eliminarPieza(tablero, filas, columnas, fila - 1, columna, valor_ini, cont);
		if (izquierda) eliminarPieza(tablero, filas, columnas, fila, columna - 1, valor_ini, cont);
		if (abajo) eliminarPieza(tablero, filas, columnas, fila + 1, columna, valor_ini, cont);
		if (derecha) eliminarPieza(tablero, filas, columnas, fila, columna + 1, valor_ini, cont);
	}
	else {
		//SI NO COINICIDE EL VALOR, HAY QUE COMPROBAR SI ES UNA BOMBA, PERO SÓLO HAY QUE EXPLOTARLA SI ES LA PRIMERA PIEZA ELIMINADA
		if ((*cont == 0) && (valor_act>6)) {
			//ES UNA BOMBA Y HAY QUE EXPLOTARLA
			*cont = 2;
			switch (valor_act) {
			case 7: //BOMBA 5 PIEZAS HORIZONTAL
				bombaRotorH(tablero, filas, columnas, fila, columna);
				break;
			case 8: //BOMBA 5 PIEZAS VERTICAL
				bombaRotorV(tablero, filas, columnas, fila, columna);
				break;
			case 9: //BOMBA 6 PIEZAS
				bombaTNT(tablero, filas, columnas, fila, columna);
				break;
			default://BOMBA 7 PIEZAS
				bombaPuzzle(tablero, filas, columnas, fila, columna);
				break;
			}
		}
		else {
			//ES UNA BOMBA PERO NO HAY QUE EXPLOTARLA, ES ADYACENTE A LAS QUE HAY QUE EXPLOTAR
		}
	}
}

__device__ void bombaRotorH(int* tablero, int filas, int columnas, int fila, int columna) {
	//BORRAR FILA
	for (int i = 0; i < columnas; i++) {
		tablero[fila*columnas + i] = 0;
	}
}

__device__ void bombaRotorV(int* tablero, int filas, int columnas, int fila, int columna) {
	//BORRAR COLUMNA
	for (int i = 0; i < filas; i++) {
		tablero[i*columnas + columna] = 0;
	}
}

__device__ void bombaTNT(int* tablero, int filas, int columnas, int fila, int columna) {
	tablero[fila*columnas + columna] = 0;
	bool arriba = true;
	bool abajo = true;
	bool izquierda = true;
	bool derecha = true;

	if (fila < 1) arriba = false;
	if (columna < 1) izquierda = false;
	if (fila + 1 >= filas) abajo = false;
	if (columna + 1 >= columnas) derecha = false;

	if (arriba) tablero[(fila - 1)*columnas + columna] = 0;
	if (izquierda) tablero[fila*columnas + (columna - 1)] = 0;
	if (abajo) tablero[(fila + 1)*columnas + columna] = 0;
	if (derecha) tablero[fila*columnas + (columna + 1)] = 0;
	if (arriba&&izquierda) tablero[(fila - 1)*columnas + (columna - 1)] = 0;
	if (arriba&&derecha) tablero[(fila - 1)*columnas + (columna + 1)] = 0;
	if (abajo&&izquierda) tablero[(fila + 1)*columnas + (columna - 1)] = 0;
	if (abajo&&derecha) tablero[(fila + 1)*columnas + (columna + 1)] = 0;
}

__device__ void bombaPuzzle(int* tablero, int filas, int columnas, int fila, int columna) {
	int valor = tablero[fila*columnas + columna] - 10;
	tablero[fila*columnas + columna] = 0;
	for (int i = 0; i < filas; i++) {
		for (int j = 0; j < columnas; j++) {
			if (tablero[i*columnas + j] == valor) tablero[i*columnas + j] = 0;
		}
	}
}