官网中两种：Servlet 和 WebFlux
![](spring%20security笔记.assets/file-20251226144524751.png)
1. **Getting Started (Servlet)**：这是基于传统的 Servlet 技术的 Spring Security 配置。Servlet 容器（如 Tomcat）提供了一个标准的线程模型来处理请求。在这种模式下，Spring Security 将在 Servlet 请求的生命周期内处理安全性，适用于同步模型的 Web 应用。

2. **Getting Started (WebFlux)**：这是基于 Spring WebFlux 的配置，适用于响应式编程模型，特别是当应用程序使用非阻塞的方式（如 Reactor）处理请求时。在这种模式下，Spring Security 配置适用于响应式应用程序，支持异步、非阻塞的 I/O 操作。

总结来说，Servlet 模式适合传统的基于同步线程的应用，而 WebFlux 模式适用于现代的响应式 Web 应用。
本篇笔记主要学习**Servlet**

# 补充：高性能网络编程之 Reactor 网络模型
## 前言

网络框架的设计离不开 I/O 线程模型，线程模型的优劣直接决定了系统的吞吐量、可扩展性、安全性等。

目前主流的网络框架，在网络 IO 处理层面几乎都采用了「I/O 多路复用方案」，这是服务端应对高并发的性能利器。

进一步看，当上升到整个网络模块时，另一个常常听说的模式出现了 ---- 「Reactor模式」，也叫反应器模式，本质是一个事件转发器，是网络模块核心中枢，负责将读写事件分发给对应的读写事件处理者。

通常情况下，reactor 模式的网络 IO 层会采用经典的 IO 多路复用方案，强强联手，妥妥的高性能的代名词、扛把子！！！是众多开源项目普遍的解决方案。

## 一、网络IO进化史

我们先来看看，一个网络请求在服务端经历了哪些阶段：

![](spring%20security笔记.assets/file-20251226145027071.png)

可以看到，网络请求先后经历 服务器网卡、内核、连接建立、数据读取、业务处理、数据写回等一系列过程。

其中，连接建立(accept)、数据读取(read)、数据写回(write)等操作都需要操作系统内核提供的系统调用，最终由内核与网卡进行数据交互，这些 IO 调用消耗一般是比较高的，比如 IO 等待、数据传输等。

最初的处理方式是，每个连接都用独立的一个线程来处理这一系列的操作，即 建立连接、数据读写、业务逻辑处理；这样一来最大的弊端在于，N 个连接就需要 N 个线程资源，消耗巨大。

所以，在网络模型演化过程中，不断的对这几个阶段进行拆分，比如，将建立连接、数据读写、业务逻辑处理等关键阶段分开处理。这样一来，每个阶段都可以考虑使用单线程或者线程池来处理，极大的节约线程资源，又能获得超高性能。

### 1.非阻塞IO

**阻塞IO**：通常是用户态线程通过系统调用阻塞读取网卡传递的数据，我们知道，在 TCP 三次握手建立连接之后，真正等待数据的到来需要一定时间；

这个时候，在该模式下用户线程会一直阻塞等待网卡数据准备就绪，直到完成数据读写完成；可以看到，用户线程大部分都在等待 IO 事件就绪，造成资源的急剧浪费。

![](spring%20security笔记.assets/file-20251226152051078.png)

**非阻塞IO**：与阻塞 IO 相反，如果数据未就绪会直接返回，应用层轮询读取/查询，直到成功读取数据。

![](https://pic4.zhimg.com/v2-390ba3cb8877545eaead44ed63abdc3f_1440w.jpg)

**I/O多路复用**：是非阻塞IO的一种特例，也是目前最经典、最常用的高性能IO模型。其具体处理方式是：先查询 IO 事件是否准备就绪，当 IO 事件准备就绪了，则会真正的通过系统调用实现数据读写；

查询操作，不管是否数据准备就绪都会立即返回，即非阻塞；因此，通常情况下，会通过轮训来不断监听 IO 事件是否准备就绪；因为操作是非阻塞的，这个过程中通常只需及少量线程（一般一个线程即可）来处理这个轮训操作，极大的解决阻塞模式下 IO 枯竭问题。

这种一个线程就可以监听所有网络连接的 IO 事件是否准备就绪的模式，就是大名鼎鼎的IO多路复用。

![](https://pic4.zhimg.com/v2-089d8cd5b0ad4a134f6247198ff3ec13_1440w.jpg)

### 2.事件驱动？

前面我们提到：将一个正常的请求分成多段来看待，每一段都可以分别进行优化（看场景需要）。

经典的一种切分方法是将「连接」和「业务线程」分开处理，当「连接层」有事件触发时提交给「业务线程」，避免了业务线程因「网络数据处于准备中」导致的长时间等待问题，节省线程资源，这就是大名鼎鼎的`事件驱动模型`。

![](https://pic3.zhimg.com/v2-51514a73e6b206a7c609cba0cc410df0_1440w.jpg)

事件驱动的核心是，以事件为连接点，当有IO事件准备就绪时，以事件的形式通知相关线程进行数据读写，进而业务线程可以直接处理这些数据，这一过程的后续操作方，都是被动接收通知，看起来有点像回调操作；

这种模式下，IO 读写线程、业务线程工作时，必有数据可操作执行，不会在 IO 等待上浪费资源，这便是事件驱动的核心思想。

举个简单例子，10个士兵接到命令，在接下来将执行秘密任务，但具体时间待定；一种方式时，这10个士兵自己掌握主动权，隔一段时间就会自己询问将军是否准备执行任务，这种模式比较低下，因为士兵需要花很多精力自己去确认任务执行时间，同时也会耽搁自己的训练时间。

另一种方式为，士兵接到即将执行秘密任务的通知后，会自己做好准备随时执行，在最终执行命名没下达之前，会继续自己的日常训练；等需要执行任务时，将军会立刻通知士兵们立即行动；很显然，这种模式，士兵们的时间资源并没有浪费。这便是事件驱动的优势所在。

好了，到此相信你已经明白了什么是事件驱动了。Reactor 模型的核心便是事件驱动，同时，为了让其网络 IO 层拥有了高性能的能力，一般会采用 IO 多路复用处理方案。


### 3.Reactor 模型？

有了上文的基础，理解 Reactor 模型就很容易了，其核心是事件驱动，换句话说，`Reactor 是事件驱动模型的一种实现`。

你可以理解为 Reactor 模型中的反应器角色，类似于事件转发器 ----承接连接建立、IO处理以及事件分发，示例图下：

![](https://pic3.zhimg.com/v2-0a3f46be239d76f896ffab3d39731f64_1440w.jpg)

Reactor 模式由 Reactor 线程、Handlers 处理器两大角色组成，两大角色的职责分别如下：

- Reactor 线程的职责：主要负责连接建立、监听IO事件、IO事件读写以及将事件分发到Handlers 处理器。
- Handlers 处理器（业务处理）的职责：非阻塞的执行业务处理逻辑。

## 二、大话 Reactor 模型

好了，到了这里便开始介绍我们的主角：Reactor 模型。

前面我们提到，网络模型演化过程中，将建立连接、IO等待/读写以及事件转发等操作分阶段处理，然后可以对不同阶段采用相应的优化策略来提高性能。

也正是如此，Reactor 模型在不同阶段都有相关的优化策略，常见的有以下三种方式呈现：

- 单线程模型
- 多线程模型
- 主从多线程模型

从某些方面来说，其实主要有`单线程`和`多线程`两种模型；其中，多线程模型就包含了多线程模型(Woker线程池)和主从多线程模型。多线程 Reactor 的演进分为两个方面：

- 升级 Handler。既要使用多线程，又要尽可能高效率，则可以考虑使用线程池。
- 升级 Reactor。可以考虑引入多个Selector（选择器），提升选择大量通道的能力。

**不过，为了方便表述，还是细分为三种模型来进行表述。**

我们常说的`多线程模型`一般是指在 Worker 端使用多线程来提升业务上的处理能力。

而主从多线程模型，将 建立连接 和 IO事件监听/读写以及事件分发 两部分用不同的线程处理，这样各司其职，能有效利用系统多核资源；同时为提高事件处理的效率，通常可以使用线程池来处理 IO事件监听/读写以及事件分发这部分操作。

另外，主从多线程模型通常情况下，Worker 端也会采用线程池来处理业务。这样一看，这三种 Reactor 模型其实是层层递进，不断的提升系统的吞吐量。当然，这一系列变换使用都需要结合实际场景考虑，但终究万变不离其宗。

接下来我们将详细分析这几种模型，继续往下看。

### 1.单线程模型

模型图如下：

![](https://pic2.zhimg.com/v2-dae5287666bb6dd3d361d4f673a35e0f_1440w.jpg)

上图描述了 Reactor 的单线程模型结构，在 Reactor 单线程模型中，所有 I/O 操作（包括连接建立、数据读写、事件分发等）、业务处理，都是由一个线程完成的。单线程模型逻辑简单，缺陷也十分明显：

- 一个线程支持处理的连接数非常有限，CPU 很容易打满，性能方面有明显瓶颈；
- 当多个事件被同时触发时，只要有一个事件没有处理完，其他后面的事件就无法执行，这就会造成消息积压及请求超时；
- 线程在处理 I/O 事件时，Select 无法同时处理连接建立、事件分发等操作；
- 如果 I/O 线程一直处于满负荷状态，很可能造成服务端节点不可用。

在单线程 Reactor 模式中，Reactor 和 Handler 都在同一条线程中执行。这样，带来了一个问题：当其中某个 Handler 阻塞时，会导致其他所有的 Handler 都得不到执行。

在这种场景下，被阻塞的 Handler 不仅仅负责输入和输出处理的传输处理器，还包括负责新连接监听的 Acceptor 处理器，可能导致服务器无响应。这是一个非常严重的缺陷，导致单线程反应器模型在生产场景中使用得比较少。

### 2.多线程模型

![](https://picx.zhimg.com/v2-1161fb3d6420a5b32b06321ba288aabb_1440w.jpg)

由于单线程模型有性能方面的瓶颈，多线程模型作为解决方案就应运而生了。

Reactor 多线程模型将业务逻辑交给多个线程进行处理。除此之外，多线程模型其他的操作与单线程模型是类似的，比如连接建立、IO事件读写以及事件分发等都是由一个线程来完成。

当客户端有数据发送至服务端时，Select 会监听到可读事件，数据读取完毕后提交到业务线程池中并发处理。

一般的请求中，耗时最长的一般是业务处理，所以用一个线程池（worker 线程池）来处理业务操作，在性能上的提升也是非常可观的。

当然，这种模型也有明显缺点，连接建立、IO 事件读取以及事件分发完全有单线程处理；比如当某个连接通过系统调用正在读取数据，此时相对于其他事件来说，完全是阻塞状态，新连接无法处理、其他连接的 IO、查询 IO 读写以及事件分发都无法完成。

对于像 Nginx、Netty 这种对高性能、高并发要求极高的网络框架，这种模式便显得有些吃力了。因为，无法及时处理新连接、就绪的 IO 事件以及事件转发等。

接下来，我们看看主从多线程模型是如何解决这个问题的。

### 3.主从多线程模型

![](https://pic3.zhimg.com/v2-b59c465362643a241429842791a45e3c_1440w.jpg)

主从 Reactor 模型要想解决这个问题，同样需要从我们前面介绍的几个阶段中的某一个或者多个进行优化处理。

**既然是主从模式，那谁主谁从呢？哪个模块使用主从呢？**

在多线程模型中，我们提到，其主要缺陷在于同一时间无法处理**大量新连接**、**IO就绪事件**；因此，将主从模式应用到这一块，就可以解决这个问题。

主从 Reactor 模式中，分为了主 Reactor 和 从 Reactor，分别处理 `新建立的连接`、`IO读写事件/事件分发`。

- 一来，主 Reactor 可以解决同一时间大量新连接，将其注册到从 Reactor 上进行IO事件监听处理
- 二来，IO事件监听相对新连接处理更加耗时，此处我们可以考虑使用线程池来处理。这样能充分利用多核 CPU 的特性，能使更多就绪的IO事件及时处理。

简言之，主从多线程模型由多个 Reactor 线程组成，每个 Reactor 线程都有独立的 Selector 对象。MainReactor 仅负责处理客户端连接的 Accept 事件，连接建立成功后将新创建的连接对象注册至 SubReactor。再由 SubReactor 分配线程池中的 I/O 线程与其连接绑定，它将负责连接生命周期内所有的 I/O 事件。

在海量客户端并发请求的场景下，主从多线程模式甚至可以适当增加 SubReactor 线程的数量，从而利用多核能力提升系统的吞吐量。

## 总结

相信到这里，你已经很清楚 Reactor 模型扮演什么样的角色了。其核心是围绕`事件驱动`模型

- 一方面监听并处理IO事件。
- 另一方面将这些处理好的事件分发业务线程处理。

而几种 Reactor 模型的演进，不过是在这几个阶段中优化升级、层层递进。

我们再重点回顾多线程模式（多线程模式和主从多线程模式），其工作模式大致如下：

- 将负责数据传输处理的 IOHandler 处理器的执行放入独立的线程池中。这样，业务处理线程与负责新连接监听的反应器线程就能相互隔离，避免服务器的连接监听受到阻塞。
- 如果服务器为多核的 CPU，可以将反应器线程拆分为多个子反应器（SubReactor）线程；同时，引入多个选择器，并且为每一个SubReactor引入一个线程，一个线程负责一个选择器的事件轮询。这样充分释放了系统资源的能力，也大大提升了反应器管理大量连接或者监听大量传输通道的能力。

Reactor（反应器）模式是高性能网络编程在设计和架构层面的基础模式，算是基础的原理性知识。只有彻底了解反应器的原理，才能真正构建好高性能的网络应用、轻松地学习和掌握高并发通信服务器与框架。

### C++代码实现reactor模型

```text
#include <stdio.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <fcntl.h>

#include <unistd.h>

#include <pthread.h>
#include <sys/epoll.h>
#include <string.h>
#include <stdlib.h>


#define BUFFER_LENGTH	128
#define EVENTS_LENGTH	128

#define PORT_COUNT		100
#define ITEM_LENGTH		1024


// listenfd, clientfd
struct sock_item { // conn_item

	int fd; // clientfd

	char *rbuffer;
	int rlength; //

	char *wbuffer;
	int wlength;
	
	int event;

	void (*recv_cb)(int fd, char *buffer, int length);
	void (*send_cb)(int fd, char *buffer, int length);

	void (*accept_cb)(int fd, char *buffer, int length);

};

struct eventblock {
	struct sock_item *items; 
	struct eventblock *next;
};

struct reactor {
	int epfd; //epoll
	int blkcnt;

	struct eventblock *evblk; 
};

int reactor_resize(struct reactor *r) { // new eventblock

	if (r == NULL) return -1;	

	struct eventblock *blk = r->evblk;

	while (blk != NULL && blk->next != NULL) {
		blk = blk->next;
	}

	struct sock_item* item = (struct sock_item*)malloc(ITEM_LENGTH * sizeof(struct sock_item));
	if (item == NULL) return -4;
	memset(item, 0, ITEM_LENGTH * sizeof(struct sock_item));

	printf("-------------\n");
	struct eventblock *block = malloc(sizeof(struct eventblock));
	if (block == NULL) {
		free(item);
		return -5;
	}
	memset(block, 0, sizeof(struct eventblock));

	block->items = item;
	block->next = NULL;

	if (blk == NULL) {
		r->evblk = block;
	} else {
		blk->next = block;
	}
	r->blkcnt ++;

	return 0;
}


struct sock_item* reactor_lookup(struct reactor *r, int sockfd) {

	if (r == NULL) return NULL;
	//if (r->evblk == NULL) return NULL;
	if (sockfd <= 0) return NULL;

	printf("reactor_lookup --> %d\n", r->blkcnt); //64
	int blkidx = sockfd / ITEM_LENGTH;
	while (blkidx >= r->blkcnt) {
		reactor_resize(r);
	}

	int i = 0;
	struct eventblock *blk = r->evblk;
	while (i ++ < blkidx && blk != NULL) {
		blk = blk->next;
	}

	printf("当前itemsSize: %ld",sizeof(&blk->items));
	return  &blk->items[sockfd % ITEM_LENGTH];
}

// thread --> fd
void *routine(void *arg) {

	int clientfd = *(int *)arg;

	while (1) {
		
		unsigned char buffer[BUFFER_LENGTH] = {0};
		int ret = recv(clientfd, buffer, BUFFER_LENGTH, 0);
		if (ret == 0) {
			close(clientfd);
			break;
			
		}
		printf("buffer : %s, ret: %d\n", buffer, ret);

		ret = send(clientfd, buffer, ret, 0); // 

	}

}


int init_server(short port) {

	int listenfd = socket(AF_INET, SOCK_STREAM, 0);  // 
	if (listenfd == -1) return -1;
// listenfd

	printf("开放端口： %d \n",port);
	struct sockaddr_in servaddr;
	servaddr.sin_family = AF_INET;
	servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
	servaddr.sin_port = htons(port);

	if (-1 == bind(listenfd, (struct sockaddr*)&servaddr, sizeof(servaddr))) {
		return -2;
	}

#if 1 // nonblock
	int flag = fcntl(listenfd, F_GETFL, 0);
	flag |= O_NONBLOCK;
	fcntl(listenfd, F_SETFL, flag);
#endif

	listen(listenfd, 10);

	return listenfd;
}


int is_listenfd(int *fds, int connfd) {

	printf("listenfd ");
	int i = 0;
	for (i = 0;i < PORT_COUNT;i ++) {
		if (fds[i] == connfd) {
			return 1;
		}
	}

	return 0;
}

// socket --> 
// bash --> execve("./server", "");
// 
// 0, 1, 2
// stdin, stdout, stderr
int main() {

// block


///  **********
	struct reactor *r = (struct reactor*)calloc(1, sizeof(struct reactor));
	if (r == NULL) {
		return -3;
	}
	//memset();

	r->epfd = epoll_create(1);
	struct epoll_event ev, events[EVENTS_LENGTH];

 	
	int sockfds[PORT_COUNT] = {0};
	int i = 0;
	for (i = 0;i < PORT_COUNT;i ++) {
		sockfds[i] = init_server(9999 + i);

		ev.events = EPOLLIN;
		ev.data.fd = sockfds[i]; //

		epoll_ctl(r->epfd, EPOLL_CTL_ADD, sockfds[i], &ev);
	}
	/// ************** //

	 // 
	

	while (1) { // 7 * 24 

		int nready = epoll_wait(r->epfd, events, EVENTS_LENGTH, -1); // -1, ms 
		//printf("------- %d\n", nready);
		
		int i = 0;
		for (i = 0;i < nready;i ++) {
			int clientfd = events[i].data.fd;
			
			if (is_listenfd(sockfds, clientfd)) { // accept

				struct sockaddr_in client;
				socklen_t len = sizeof(client);
				int connfd = accept(clientfd, (struct sockaddr*)&client, &len);
				printf("有客户端连接.. connfd: %d 、 clientfd： %d \n",connfd,clientfd);

				if (connfd == -1) break;
				
				if (connfd % 1000 == 999) {
				
					printf("accept: %d\n", connfd);

				}

#if 1 // nonblock
				int flag = fcntl(connfd, F_GETFL, 0);
				flag |= O_NONBLOCK;
				fcntl(connfd, F_SETFL, flag);
#endif
				
				ev.events = EPOLLIN;
				ev.data.fd = connfd;
				epoll_ctl(r->epfd, EPOLL_CTL_ADD, connfd, &ev);
#if 0
				r->items[connfd].fd = connfd;
			
				r->items[connfd].rbuffer = calloc(1, BUFFER_LENGTH);
				r->items[connfd].rlength = 0;
				
				r->items[connfd].wbuffer = calloc(1, BUFFER_LENGTH);
				r->items[connfd].wlength = 0;

				r->items[connfd].event = EPOLLIN;
#else

				struct sock_item *item = reactor_lookup(r, connfd);
				item->fd = connfd;
				item->rbuffer = calloc(1, BUFFER_LENGTH);
				item->rlength = 0;

				item->wbuffer = calloc(1, BUFFER_LENGTH);
				item->wlength = 0;
#endif				
			} else if (events[i].events & EPOLLIN) { //clientfd

				//char rbuffer[BUFFER_LENGTH] = {0};

				struct sock_item *item = reactor_lookup(r, clientfd);

				char *rbuffer = item->rbuffer;
				char *wbuffer = item->wbuffer;
				
				int n = recv(clientfd, rbuffer, BUFFER_LENGTH, 0);
				if (n > 0) {
					//rbuffer[n] = '\0';

					printf("recv: %s, n: %d\n", rbuffer, n);

					memcpy(wbuffer, rbuffer, BUFFER_LENGTH);

					ev.events = EPOLLOUT;
					ev.data.fd = clientfd;

					epoll_ctl(r->epfd, EPOLL_CTL_MOD, clientfd, &ev);
					
				} else if (n == 0) {

					free(rbuffer);
					free(wbuffer);
					
					item->fd = 0;

					close(clientfd);
				}
				
			} else if (events[i].events & EPOLLOUT) {

				
				struct sock_item *item = reactor_lookup(r, clientfd);
				char *wbuffer = item->wbuffer;
				
				int sent = send(clientfd, wbuffer, BUFFER_LENGTH, 0); //
				printf("sent: %d\n", sent);

				ev.events = EPOLLIN;
				ev.data.fd = clientfd;

				epoll_ctl(r->epfd, EPOLL_CTL_MOD, clientfd, &ev);
				
				
			}

		}

	}
	

}
```



# 一、架构
## 1. Filter回顾

![](spring%20security笔记.assets/file-20251228102616940.png)
客户端向应用程序发送一个请求，容器创建一个FilterChain，其中包含Filter示例和Servlet，应该根据请求URI的路径来处理 `HttpServletRequest`。在Spring MVC应用程序中，Servlet是 [`DispatcherServlet`](https://docs.spring.io/spring-framework/docs/6.1.0-M2/reference/html/web.html#mvc-servlet) 的一个实例。一个 `Servlet` 最多可以处理一个 `HttpServletRequest` 和 `HttpServletResponse`。然而，可以使用多个 `Filter` 来完成如下工作。

- 防止下游的 `Filter` 实例或 `Servlet` 被调用。在这种情况下，`Filter` 通常会使用 `HttpServletResponse` 对客户端写入响应。
    
- 修改下游的 `Filter` 实例和 `Servlet` 所使用的 `HttpServletRequest` 或 `HttpServletResponse`。
    

过滤器的力量来自于传入它的 `FilterChain`。

`FilterChain` Usage Example
```java
public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) {
	// do something before the rest of the application
    chain.doFilter(request, response); // invoke the rest of the application
    // do something after the rest of the application
}
```

由于一个 `Filter` 只影响下游的 `Filter` 实例和 `Servlet`，所以每个 `Filter` 的调用顺序是非常重要的。

## 2. DelegatingFilterProxy
Spring 提供了一个名为 [`DelegatingFilterProxy`](https://docs.spring.io/spring-framework/docs/6.1.0-M2/javadoc-api/org/springframework/web/filter/DelegatingFilterProxy.html) 的 `Filter` 实现，允许在 Servlet 容器的生命周期和 Spring 的 `ApplicationContext` 之间建立桥梁。Servlet容器允许通过使用自己的标准来注册 `Filter` 实例，但它不知道 Spring 定义的 Bean。你可以通过标准的Servlet容器机制来注册 `DelegatingFilterProxy`，但将所有工作委托给实现 `Filter` 的Spring Bean。

下面是 `DelegatingFilterProxy` 如何融入 [`Filter` 实例和 `FilterChain` 的](https://springdoc.cn/spring-security/servlet/architecture.html#servlet-filters-review)图片。
![](spring%20security笔记.assets/file-20251228103020224.png)
`DelegatingFilterProxy` 从 `ApplicationContext` 查找 _Bean Filter0_，然后调用 _Bean Filter0_。下面的列表显示了 `DelegatingFilterProxy` 的伪代码。

```java
public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) {
	Filter delegate = getFilterBean(someBeanName); // 1
	delegate.doFilter(request, response); // 2
}
```

| 1   | 延迟地获取被注册为Spring Bean的 Filter。 对于 [DelegatingFilterProxy](https://springdoc.cn/spring-security/servlet/architecture.html#servlet-delegatingfilterproxy-figure) 中的例子，`delegate` 是 _Bean Filter0_ 的一个实例。 |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2   | 将工作委托给 Spring Bean。                                                                                                                                                                                   |

`DelegatingFilterProxy` 的另一个好处是，它允许延迟查找 `Filter` Bean实例。这一点很重要，因为在容器启动之前，容器需要注册 `Filter` 实例。然而， Spring 通常使用 `ContextLoaderListener` 来加载 Spring Bean，这在需要注册 `Filter` 实例之后才会完成。

**问题：DelegatingFilterProxy是如何实现延迟查找的？是因为只要是Spring Bean就能实现延迟，还是DelegatingFilterProxy让FIlter 的Spring Bean实现了延迟查找？**
> 延迟查找的机制：
> - `DelegatingFilterProxy` 会在 Servlet 容器启动时被注册为一个 `Filter`，但它并不会立即去查找 Spring 容器中的 `Filter` Bean。
> - 在请求到达时，`DelegatingFilterProxy` 会通过 Spring 的 `ApplicationContext` 查找 `targetBeanName` 对应的 `Filter` Bean 实例。
> - 如果 `Filter` Bean 没有被初始化，Spring 会在此时创建和注入该 `Filter` Bean。这就是延迟加载的实现。也就是说，`DelegatingFilterProxy` 并不会在容器启动时就创建 `Filter` 实例，而是等到实际需要使用时才会去查找并创建对应的 `Filter`。
    


### 3. **DelegatingFilterProxy**

- `DelegatingFilterProxy` 是 Spring 提供的一个 `Filter` 实现，它允许在 **Servlet 容器** 的生命周期和 **Spring 的 ApplicationContext** 之间建立桥梁。
    
- 它的作用是从 Spring 容器中延迟加载实际的 `Filter` Bean，这使得 `Filter` 可以在 Spring 管理下运行，并且可以通过 Spring 的依赖注入机制进行管理。
    

### 4. **FilterChainProxy 与 SecurityFilterChain**

- `FilterChainProxy` 是 Spring Security 中的一个特殊 `Filter`，它通过 `SecurityFilterChain` 来确定当前请求应该执行哪些 Spring Security 过滤器。
    
- `SecurityFilterChain` 用来管理多个安全相关的 `Filter`，它根据请求的 URL 和其他条件来动态选择和执行匹配的 `Filter`。例如，某些 `Filter` 可能只对特定路径或请求类型生效。
    

### 5. **如何添加自定义 Filter**

- 在 Spring Security 中，添加自定义 `Filter` 通常是在 `SecurityFilterChain` 配置中通过 `addFilterBefore()`、`addFilterAfter()` 或 `addFilterAt()` 方法实现的。这些方法允许你将自定义 `Filter` 插入到 Spring Security 的默认过滤链中。
    
- 例如，可以添加一个用于处理租户 ID 的 `TenantFilter`，确保在认证后检查租户权限。
    

### 6. **Filter 注册机制**

- 尽管你可以在 `Filter` 类上使用 `@Component` 注解，使其成为 Spring 管理的 Bean，但这并不会自动将其注册到 **Servlet 容器** 的过滤链中。你需要显式地将其通过 `FilterRegistrationBean` 或 `SecurityFilterChain` 注册到 Spring Security 的过滤链中。
    
- 使用 `FilterRegistrationBean` 可以控制 `Filter` 的 URL 映射、顺序等，避免 `Filter` 被重复注册。
    

### 7. **处理异常与请求缓存**

- **ExceptionTranslationFilter**：它负责将 `AccessDeniedException` 和 `AuthenticationException` 转换为相应的 HTTP 响应（如 401 或 403 错误），并引导用户进行认证或拒绝访问。
    
- **RequestCache**：用于保存用户未认证时请求的 URL，用户成功认证后可以重新发起该请求。这对于处理认证前访问受保护资源的情况非常有用。
    

### 8. **Spring Security 的日志机制**

- Spring Security 提供了详尽的日志记录功能，特别是在调试认证和授权相关的问题时。你可以通过调整日志级别来记录详细的 `Filter` 调用和错误信息，帮助你更清晰地了解请求的安全处理过程。
    

### 总结：

- **Filter** 在 Spring Security 中扮演着重要的角色，它们帮助你在不同的请求处理阶段执行安全检查（如认证、授权等）。
    
- Spring 使用 **FilterChainProxy** 和 **SecurityFilterChain** 来灵活地管理多个安全 `Filter`，并且根据请求的不同条件来选择合适的 `Filter` 执行。
    
- 对于自定义 `Filter`，你需要手动将其注册到 Spring Security 的过滤链中，通常是通过 `FilterRegistrationBean` 或在 `SecurityFilterChain` 中配置。
    

如果你是初学者，可以从理解 **Filter** 的工作机制开始，逐步学习如何在 Spring Security 中自定义和配置过滤器，控制请求的安全处理流程。