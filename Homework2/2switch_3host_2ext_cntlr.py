from mininet.topo import Topo
from mininet.net import Mininet
from mininet.link import TCLink
from mininet.node import RemoteController
from mininet.cli import CLI
from mininet.log import setLogLevel

class CustomTopo(Topo):
    def build(self):
        h1 = self.addHost('h1')
        h2 = self.addHost('h2')
        h3 = self.addHost('h3')
        s1 = self.addSwitch('s1')
        s2 = self.addSwitch('s2')

        self.addLink(h1, s1)
        self.addLink(h2, s1)
        self.addLink(s1, s2)
        self.addLink(s2, h3)

topos = {'mytopo': CustomTopo}

if __name__ == '__main__':
    setLogLevel('info')

    topo = CustomTopo()
    net = Mininet(topo=topo, controller=None, build=False, link=TCLink)

    c0 = net.addController('c0', controller=RemoteController, ip='127.0.0.1', port=6633)
    c1 = net.addController('c1', controller=RemoteController, ip='127.0.0.1', port=6653)

    net.start()
    CLI(net)
    net.stop()
