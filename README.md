# CloudHP

Idées pour le déploiement sur OpenStack :
-Installer une VM avec Docker, installer tous les services dessus avec le docker-compose du projet
=> La + simple mais pas très intéressante, si la VM tombe en panne, tout s'arrête.

-1 VM par container docker. On garde la facilité de la gestion des dépendances de Docker
=> Nécessite de configurer des choses dans Openstack (réseau, ports...)

-Utiliser des solutions + avancées comme Docker Swarm, Kubernetes...
=> + compliqué a priori
