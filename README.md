# Proyecto Control de Combustible Bolivia
Este documento README tiene la finalidad de explicar el objetivo, desarrollo y producción durante la realización de la base de datos implementada en la gestión del combustible en Bolivia, desde la producción y distribución, hasta la comercialización al cliente final.
## Sistema de Control de Combustible Bolivia

Base de datos para un sistema de control, distribución y comercialización de carburantes en Bolivia.

El proyecto está desarrollado inicialmente con PostgreSQL 17 y Supabase. La base de datos contempla el control de personas, vehículos, cupos semanales de combustible subvencionado, estaciones de servicio, surtidores, cargas de combustible, biometría, alertas, bloqueos, inventarios, reclamos y auditoría.
### 1. Tecnologías Utilizadas 
* PostgreSQL 17
* Supabase
* Supabase CLI
* Docker
* SQL / PLpgSQL
* Git
Supabase se utiliza actualmente como entorno de desarrollo y administración de PostgreSQL.

La arquitectura de la base de datos se diseñó procurando facilitar una futura migración hacia Oracle.
### 2. Requisitos previos
Para ejecutar la base de datos localmente se necesita:

**Git:** Permite clonar el repositorio. Comprobar instalación:

`git --version`


**Docker:** Supabase ejecuta PostgreSQL y sus servicios mediante contenedores. Se recomienda utilizar Docker Desktop. Comprobar:
`docker --version`
>[!CAUTION] OJO
>Docker debe encontrarse iniciado antes de ejecutar Supabase.

**Supabase CLI:** Comprobar si está instalado.


`supabase --version`

Si se utiliza Supabase mediante npm, los comandos pueden ejecutarse como:
npx supabase
